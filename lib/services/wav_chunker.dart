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

/// 분할된 한 청크: 독립 재생 가능한 WAV 바이트 + 원본 기준 시작 오프셋.
class WavChunk {
  const WavChunk({required this.bytes, required this.offset});

  final List<int> bytes;
  final Duration offset;
}

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

/// [wav]를 [chunk] 길이 단위로 잘라 각각 독립 WAV 바이트로 만든다.
///
/// WAV로 파싱되지 않으면(테스트용 더미 등) 원본 그대로 1청크로 반환한다. 청크 경계는
/// 16-bit 샘플 프레임(`channels*2`바이트)에 정렬해 샘플이 쪼개지지 않게 한다.
List<WavChunk> splitWav(List<int> wav, {required Duration chunk}) {
  final info = readWavInfo(wav);
  if (info == null || chunk <= Duration.zero) {
    return <WavChunk>[WavChunk(bytes: wav, offset: Duration.zero)];
  }

  final frameBytes = info.channels * 2;
  int chunkBytes = info.bytesPerSecond * chunk.inMilliseconds ~/ 1000;
  // 프레임 정렬 + 최소 1프레임.
  chunkBytes -= chunkBytes % frameBytes;
  if (chunkBytes < frameBytes) chunkBytes = frameBytes;

  final dataStart = info.dataOffset;
  final dataEnd = info.dataOffset + info.dataLength;
  if (dataEnd - dataStart <= chunkBytes) {
    return <WavChunk>[WavChunk(bytes: wav, offset: Duration.zero)];
  }

  final chunks = <WavChunk>[];
  var pos = dataStart;
  var index = 0;
  while (pos < dataEnd) {
    final end = (pos + chunkBytes) > dataEnd ? dataEnd : pos + chunkBytes;
    final pcm = wav.sublist(pos, end);
    chunks.add(WavChunk(
      bytes: _wrapWav(pcm, info.sampleRate, info.channels),
      offset: Duration(milliseconds: index * chunk.inMilliseconds),
    ));
    pos = end;
    index++;
  }
  return chunks;
}

/// PCM 데이터에 표준 44바이트 16-bit WAV 헤더를 붙여 완전한 WAV 바이트를 만든다.
List<int> _wrapWav(List<int> pcm, int sampleRate, int channels) {
  final header = buildWavHeader(
    sampleRate: sampleRate,
    channels: channels,
    dataLength: pcm.length,
  );
  return <int>[...header, ...pcm];
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
