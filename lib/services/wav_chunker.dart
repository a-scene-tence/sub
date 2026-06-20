import 'dart:typed_data';

/// WAV(RIFF) 헤더 정보. 16-bit PCM mono/stereo만 가정한다(네이티브 추출기 출력).
class WavInfo {
  const WavInfo({
    required this.sampleRate,
    required this.channels,
    required this.dataOffset,
    required this.dataLength,
  });

  final int sampleRate;
  final int channels;

  /// 데이터 청크 시작 바이트 오프셋(표준 헤더는 44).
  final int dataOffset;

  /// 데이터 청크 길이(바이트).
  final int dataLength;

  /// 16-bit 샘플 기준 초당 바이트 수.
  int get bytesPerSecond => sampleRate * channels * 2;
}

/// 한 청크의 경계 계획(바이트를 담지 않는다 — 디스크에서 필요 시 읽기 위함).
///
/// [dataStart]는 데이터 영역 내 상대 오프셋(파일 절대 오프셋은 `dataOffset + dataStart`),
/// [length]는 읽을 PCM 바이트 수, [offset]은 원본 기준 청크 시작 시각.
typedef ChunkPlan = ({int dataStart, int length, Duration offset});

const int _headerSize = 44;

/// WAV(RIFF/WAVE) 헤더를 파싱한다. WAV가 아니거나 너무 짧으면 `null`.
///
/// 데이터 청크 위치를 정확히 찾기 위해 `fmt `/`data` 청크를 순회한다(일부 인코더는
/// 표준 44바이트 헤더와 다른 보조 청크를 넣을 수 있음).
WavInfo? readWavInfo(List<int> bytes) {
  if (bytes.length < _headerSize) return null;
  // 'RIFF' .... 'WAVE'
  if (!(bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x41 &&
      bytes[10] == 0x56 &&
      bytes[11] == 0x45)) {
    return null;
  }

  int channels = 0;
  int sampleRate = 0;
  int pos = 12; // 'WAVE' 이후 첫 서브청크.
  while (pos + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes, pos, pos + 4);
    final size = _u32le(bytes, pos + 4);
    final body = pos + 8;
    if (id == 'fmt ' && body + 16 <= bytes.length) {
      channels = _u16le(bytes, body + 2);
      sampleRate = _u32le(bytes, body + 4);
    } else if (id == 'data') {
      if (channels == 0 || sampleRate == 0) return null;
      final available = bytes.length - body;
      final dataLength = size <= available ? size : available;
      return WavInfo(
        sampleRate: sampleRate,
        channels: channels,
        dataOffset: body,
        dataLength: dataLength,
      );
    }
    // 청크는 2바이트 정렬(홀수 크기면 패딩 1바이트).
    pos = body + size + (size.isOdd ? 1 : 0);
  }
  return null;
}

/// 데이터 영역을 [chunk] 길이 단위로 나눈 **경계 목록**을 계산한다(바이트는 담지 않음).
///
/// 호출자가 각 [ChunkPlan]에 대해 디스크에서 `[dataStart, dataStart+length)` 구간만 읽어
/// 메모리 안전하게 처리하도록 한다. [totalDataBytes]는 데이터 영역의 실제 바이트 수
/// (파일 길이 - `dataOffset`). 청크 경계는 16-bit 샘플 프레임(`channels*2`)에 정렬한다.
List<ChunkPlan> planChunks(
  WavInfo info, {
  required int totalDataBytes,
  required Duration chunk,
}) {
  if (totalDataBytes <= 0) return const <ChunkPlan>[];

  final frameBytes = info.channels * 2;
  if (chunk <= Duration.zero) {
    return <ChunkPlan>[
      (dataStart: 0, length: totalDataBytes, offset: Duration.zero),
    ];
  }

  int chunkBytes = info.bytesPerSecond * chunk.inMilliseconds ~/ 1000;
  chunkBytes -= chunkBytes % frameBytes; // 프레임 정렬
  if (chunkBytes < frameBytes) chunkBytes = frameBytes;

  final plans = <ChunkPlan>[];
  var pos = 0;
  var index = 0;
  while (pos < totalDataBytes) {
    final end = (pos + chunkBytes) > totalDataBytes ? totalDataBytes : pos + chunkBytes;
    plans.add((
      dataStart: pos,
      length: end - pos,
      offset: Duration(milliseconds: index * chunk.inMilliseconds),
    ));
    pos = end;
    index++;
  }
  return plans;
}

/// 표준 44바이트 16-bit PCM WAV(RIFF/`fmt `/`data`) 헤더를 생성한다.
List<int> buildWavHeader({
  required int sampleRate,
  required int channels,
  required int dataLength,
}) {
  const bitsPerSample = 16;
  final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
  final blockAlign = channels * bitsPerSample ~/ 8;
  final b = BytesBuilder();
  void ascii(String s) => b.add(s.codeUnits);
  void u32(int v) =>
      b.add(<int>[v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  void u16(int v) => b.add(<int>[v & 0xFF, (v >> 8) & 0xFF]);

  ascii('RIFF');
  u32(36 + dataLength);
  ascii('WAVE');
  ascii('fmt ');
  u32(16);
  u16(1); // PCM
  u16(channels);
  u32(sampleRate);
  u32(byteRate);
  u16(blockAlign);
  u16(bitsPerSample);
  ascii('data');
  u32(dataLength);
  return b.toBytes();
}

int _u32le(List<int> b, int o) =>
    b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

int _u16le(List<int> b, int o) => b[o] | (b[o + 1] << 8);
