import 'package:flutter_test/flutter_test.dart';
import 'package:video_subtitle_translator/models/subtitle_cue.dart';
import 'package:video_subtitle_translator/services/cue_builder.dart';

void main() {
  group('clampOverlaps', () {
    SubtitleCue cue(int s, int e) => SubtitleCue(
          start: Duration(milliseconds: s),
          end: Duration(milliseconds: e),
          text: 't',
        );

    test('중첩 큐의 end를 다음 start로 클램프', () {
      final result = clampOverlaps(<SubtitleCue>[
        cue(0, 1500),
        cue(1000, 2000),
      ]);
      expect(result[0].end, const Duration(milliseconds: 1000));
      expect(result[1].end, const Duration(milliseconds: 2000));
    });

    test('비중첩은 변화 없음', () {
      final input = <SubtitleCue>[cue(0, 1000), cue(1000, 2000)];
      expect(clampOverlaps(input), input);
    });

    test('클램프 후 동기화 엔진 불변식(비중첩) 만족', () {
      final result = clampOverlaps(<SubtitleCue>[
        cue(0, 1500),
        cue(1000, 2000),
        cue(1800, 3000),
      ]);
      for (var i = 1; i < result.length; i++) {
        expect(result[i].start >= result[i - 1].end, isTrue);
      }
    });
  });
}
