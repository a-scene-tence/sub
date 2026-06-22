import AVFoundation
import Flutter
import Foundation

/// 영상에서 오디오 트랙을 디코드해 16-bit **mono** PCM WAV 파일을 만든다.
/// 폐기된 FFmpegKit(16KB 페이지 비호환)을 대체하는 플랫폼 네이티브 추출기.
///
/// 샘플레이트는 소스 네이티브 레이트를 유지(리샘플 없음)하며 WAV 헤더에 기록한다.
/// `AVNumberOfChannelsKey = 1`로 멀티채널을 mono 다운믹스한다.
enum AudioExtractor {
  /// 백그라운드 큐에서 추출하고 메인 큐로 [result]를 회신한다.
  ///
  /// [startMs]/[endMs]가 주어지면 그 시간 구간만 추출한다(실시간 자막용). 둘 다 nil이면 전체.
  static func extractWavAsync(
    videoPath: String, outPath: String,
    startMs: Int?, endMs: Int?, headers: [String: String]?,
    result: @escaping FlutterResult
  ) {
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let info = try extract(
          videoPath: videoPath, outPath: outPath,
          startMs: startMs, endMs: endMs, headers: headers
        )
        DispatchQueue.main.async { result(info) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "extract_failed",
            message: error.localizedDescription,
            details: nil
          ))
        }
      }
    }
  }

  private struct ExtractError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
  }

  private static func extract(
    videoPath: String, outPath: String, startMs: Int?, endMs: Int?,
    headers: [String: String]?
  ) throws -> [String: Any] {
    let url: URL
    let isRemote: Bool
    if let parsed = URL(string: videoPath), let scheme = parsed.scheme,
       scheme == "http" || scheme == "https" {
      url = parsed
      isRemote = true
    } else {
      url = URL(fileURLWithPath: videoPath)
      isRemote = false
    }

    // 원격 URL이면 헤더(UA·Referer)와 함께 연다(핫링크 보호 우회).
    var options: [String: Any] = [:]
    if isRemote, let headers = headers, !headers.isEmpty {
      options["AVURLAssetHTTPHeaderFieldsKey"] = headers
    }
    let asset = AVURLAsset(url: url, options: options)
    guard let track = asset.tracks(withMediaType: .audio).first else {
      throw ExtractError(message: "오디오 트랙 없음")
    }

    // 소스 네이티브 샘플레이트 추출(없으면 44100 폴백).
    var sampleRate = 44100
    if let formatDesc = track.formatDescriptions.first {
      let desc = formatDesc as! CMAudioFormatDescription
      if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
        sampleRate = Int(asbd.pointee.mSampleRate)
      }
    }

    let reader = try AVAssetReader(asset: asset)
    // 구간 추출: timeRange는 프레임 정확하므로 시킹 드리프트가 없다.
    if let startMs = startMs {
      let start = CMTime(value: CMTimeValue(startMs), timescale: 1000)
      let dur: CMTime = endMs != nil
        ? CMTime(value: CMTimeValue(max(0, endMs! - startMs)), timescale: 1000)
        : CMTime.positiveInfinity
      reader.timeRange = CMTimeRange(start: start, duration: dur)
    }
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
      AVNumberOfChannelsKey: 1,
      AVSampleRateKey: sampleRate,
    ]
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else {
      throw ExtractError(message: "리더 출력 구성 실패")
    }
    reader.add(output)

    guard reader.startReading() else {
      throw ExtractError(message: reader.error?.localizedDescription ?? "리더 시작 실패")
    }

    var pcm = Data()
    while reader.status == .reading {
      guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
      if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
        let length = CMBlockBufferGetDataLength(blockBuffer)
        var chunk = Data(count: length)
        chunk.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) in
          _ = CMBlockBufferCopyDataBytes(
            blockBuffer, atOffset: 0, dataLength: length, destination: ptr.baseAddress!
          )
        }
        pcm.append(chunk)
      }
      CMSampleBufferInvalidate(sampleBuffer)
    }

    if reader.status == .failed {
      throw ExtractError(message: reader.error?.localizedDescription ?? "디코드 실패")
    }
    if pcm.isEmpty {
      throw ExtractError(message: "디코드된 오디오 없음")
    }

    let wav = makeWav(pcm: pcm, sampleRate: sampleRate, channels: 1)
    try wav.write(to: URL(fileURLWithPath: outPath))

    let durationMs = Int(Double(pcm.count) / 2.0 / Double(sampleRate) * 1000.0)
    return ["sampleRate": sampleRate, "channels": 1, "durationMs": durationMs]
  }

  /// 표준 PCM WAV(RIFF/`fmt `/`data`) 바이트를 만든다.
  private static func makeWav(pcm: Data, sampleRate: Int, channels: Int) -> Data {
    let bitsPerSample = 16
    let byteRate = sampleRate * channels * bitsPerSample / 8
    let blockAlign = channels * bitsPerSample / 8
    let dataSize = pcm.count

    var header = Data()
    func ascii(_ s: String) { header.append(contentsOf: Array(s.utf8)) }
    func u32(_ v: Int) {
      header.append(contentsOf: [
        UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF),
        UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF),
      ])
    }
    func u16(_ v: Int) {
      header.append(contentsOf: [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)])
    }

    ascii("RIFF"); u32(36 + dataSize); ascii("WAVE")
    ascii("fmt "); u32(16); u16(1); u16(channels)
    u32(sampleRate); u32(byteRate); u16(blockAlign); u16(bitsPerSample)
    ascii("data"); u32(dataSize)

    var out = header
    out.append(pcm)
    return out
  }
}
