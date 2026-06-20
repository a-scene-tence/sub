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

  group('planChunks', () {
    test('고정 길이로 경계 분할 + 오프셋', () {
      // 16kHz mono 16-bit → 32000 B/s. 2초 청크 = 64000B. 데이터 160000B → 3조각.
      const info = WavInfo(
        sampleRate: 16000,
        channels: 1,
        dataOffset: 44,
        dataLength: 0, // planChunks는 totalDataBytes를 별도로 받는다.
      );
      final plans = planChunks(info,
          totalDataBytes: 160000, chunk: const Duration(seconds: 2));

      expect(plans.length, 3);
      expect(plans[0], (dataStart: 0, length: 64000, offset: Duration.zero));
      expect(plans[1],
          (dataStart: 64000, length: 64000, offset: const Duration(seconds: 2)));
      expect(plans[2],
          (dataStart: 128000, length: 32000, offset: const Duration(seconds: 4)));
    });

    test('경계는 프레임(channels*2)에 정렬', () {
      // 스테레오 16-bit → 프레임 4B. 청크 바이트가 4의 배수로 내림되어야 한다.
      const info = WavInfo(
        sampleRate: 16000,
        channels: 2,
        dataOffset: 44,
        dataLength: 0,
      );
      final plans = planChunks(info,
          totalDataBytes: 1000000, chunk: const Duration(seconds: 1));
      for (final p in plans) {
        if (p != plans.last) expect(p.length % 4, 0);
      }
    });

    test('데이터 0이면 빈 목록', () {
      const info =
          WavInfo(sampleRate: 16000, channels: 1, dataOffset: 44, dataLength: 0);
      expect(planChunks(info, totalDataBytes: 0, chunk: const Duration(seconds: 1)),
          isEmpty);
    });
  });

  group('buildWavHeader round-trip', () {
    test('생성한 헤더를 readWavInfo로 역파싱', () {
      final header =
          buildWavHeader(sampleRate: 48000, channels: 1, dataLength: 1000);
      expect(wavSampleRate(<int>[...header, ...List<int>.filled(1000, 0)]), 48000);
      expect(wavChannels(<int>[...header, ...List<int>.filled(1000, 0)]), 1);
    });
  });
}
