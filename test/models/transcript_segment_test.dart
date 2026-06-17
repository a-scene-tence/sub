import 'package:flutter_test/flutter_test.dart';
import 'package:video_subtitle_translator/models/transcript_segment.dart';

void main() {
  group('parseSttDuration', () {
    test('"1.300s" 형식', () {
      expect(parseSttDuration('1.300s'), const Duration(milliseconds: 1300));
    });

    test('정수 초 "12s"', () {
      expect(parseSttDuration('12s'), const Duration(seconds: 12));
    });

    test('"0s" 와 빈 문자열은 0', () {
      expect(parseSttDuration('0s'), Duration.zero);
      expect(parseSttDuration(''), Duration.zero);
      expect(parseSttDuration('   '), Duration.zero);
    });

    test('숫자 입력', () {
      expect(parseSttDuration(1.5), const Duration(milliseconds: 1500));
      expect(parseSttDuration(3), const Duration(seconds: 3));
    });

    test('null/음수/NaN은 0으로 클램프', () {
      expect(parseSttDuration(null), Duration.zero);
      expect(parseSttDuration('-2s'), Duration.zero);
      expect(parseSttDuration(double.nan), Duration.zero);
      expect(parseSttDuration(double.infinity), Duration.zero);
    });
  });

  group('TranscriptSegment', () {
    test('end < start 는 assert', () {
      expect(
        () => TranscriptSegment(
          start: const Duration(seconds: 2),
          end: const Duration(seconds: 1),
          text: 'x',
          languageCode: 'en-US',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('값 동등성', () {
      final a = TranscriptSegment(
        start: Duration.zero,
        end: const Duration(seconds: 1),
        text: 'hi',
        languageCode: 'en-US',
      );
      final b = TranscriptSegment(
        start: Duration.zero,
        end: const Duration(seconds: 1),
        text: 'hi',
        languageCode: 'en-US',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
