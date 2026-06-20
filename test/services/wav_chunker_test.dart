import 'package:flutter_test/flutter_test.dart';
import 'package:video_subtitle_translator/services/speech_service.dart'
    show wavSampleRate, wavChannels;
import 'package:video_subtitle_translator/services/wav_chunker.dart';

/// sampleRate/channels/16-bit로 `dataSeconds`초 분량의 더미 WAV를 만든다.
List<int> _wav({
  int sampleRate = 16000,
  int channels = 1,
  required int dataBytes,
}) {
  final header = buildWavHeader(
    sampleRate: sampleRate,
    channels: channels,
    dataLength: dataBytes,
  );
  return <int>[...header, ...List<int>.filled(dataBytes, 0)];
}

void main() {
  group('readWavInfo', () {
    test('표준 헤더 파싱', () {
      final wav = _wav(sampleRate: 48000, channels: 2, dataBytes: 800);
      final info = readWavInfo(wav)!;
      expect(info.sampleRate, 48000);
      expect(info.channels, 2);
      expect(info.dataOffset, 44);
      expect(info.dataLength, 800);
      expect(info.bytesPerSecond, 48000 * 2 * 2);
    });

    test('WAV가 아니거나 너무 짧으면 null', () {
      expect(readWavInfo(<int>[1, 2, 3]), isNull);
      expect(readWavInfo(List<int>.filled(44, 0)), isNull); // RIFF 아님
    });
  });

  group('splitWav', () {
    test('고정 길이로 분할하고 각 청크는 유효한 WAV + 오프셋', () {
      // 16kHz mono 16-bit → 32000 B/s. 5초 = 160000B. 2초 청크 → 3조각.
      final wav = _wav(dataBytes: 160000);
      final chunks = splitWav(wav, chunk: const Duration(seconds: 2));

      expect(chunks.length, 3);
      expect(chunks[0].offset, Duration.zero);
      expect(chunks[1].offset, const Duration(seconds: 2));
      expect(chunks[2].offset, const Duration(seconds: 4));

      // 각 청크는 독립 WAV로 파싱되고 레이트/채널이 보존된다.
      for (final c in chunks) {
        expect(wavSampleRate(c.bytes), 16000);
        expect(wavChannels(c.bytes), 1);
      }
      // 앞 두 조각은 64000B 데이터(+44 헤더), 마지막은 나머지 32000B.
      expect(readWavInfo(chunks[0].bytes)!.dataLength, 64000);
      expect(readWavInfo(chunks[2].bytes)!.dataLength, 32000);
    });

    test('청크보다 짧은 입력은 원본 1개 그대로', () {
      final wav = _wav(dataBytes: 1000);
      final chunks = splitWav(wav, chunk: const Duration(seconds: 50));
      expect(chunks.length, 1);
      expect(chunks.first.bytes, same(wav));
      expect(chunks.first.offset, Duration.zero);
    });

    test('WAV가 아니면 원본 1개로 폴백', () {
      final bytes = <int>[1, 2, 3, 4, 5];
      final chunks = splitWav(bytes, chunk: const Duration(seconds: 1));
      expect(chunks.length, 1);
      expect(chunks.first.bytes, same(bytes));
    });
  });
}
