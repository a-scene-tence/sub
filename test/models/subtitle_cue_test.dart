import 'package:flutter_test/flutter_test.dart';
import 'package:video_subtitle_translator/models/subtitle_cue.dart';

void main() {
  group('SubtitleCue', () {
    final c = SubtitleCue(
      start: const Duration(milliseconds: 1000),
      end: const Duration(milliseconds: 2000),
      text: '안녕',
    );

    test('duration', () {
      expect(c.duration, const Duration(milliseconds: 1000));
    });

    test('isActiveAt: 시작 포함, 종료 제외', () {
      expect(c.isActiveAt(const Duration(milliseconds: 1000)), isTrue);
      expect(c.isActiveAt(const Duration(milliseconds: 1500)), isTrue);
      expect(c.isActiveAt(const Duration(milliseconds: 2000)), isFalse);
      expect(c.isActiveAt(const Duration(milliseconds: 999)), isFalse);
    });

    test('copyWith', () {
      final c2 = c.copyWith(text: '반가워');
      expect(c2.text, '반가워');
      expect(c2.start, c.start);
      expect(c2.end, c.end);
    });

    test('end < start 는 assert', () {
      expect(
        () => SubtitleCue(
          start: const Duration(seconds: 2),
          end: const Duration(seconds: 1),
          text: 'x',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('값 동등성', () {
      final a = SubtitleCue(
          start: Duration.zero, end: const Duration(seconds: 1), text: 'a');
      final b = SubtitleCue(
          start: Duration.zero, end: const Duration(seconds: 1), text: 'a');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
