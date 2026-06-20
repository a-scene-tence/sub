import 'package:flutter_test/flutter_test.dart';
import 'package:video_subtitle_translator/widgets/player_controls.dart';

void main() {
  group('formatDuration', () {
    test('1시간 미만은 mm:ss', () {
      expect(formatDuration(Duration.zero), '00:00');
      expect(formatDuration(const Duration(seconds: 5)), '00:05');
      expect(formatDuration(const Duration(seconds: 65)), '01:05');
      expect(formatDuration(const Duration(minutes: 12, seconds: 34)), '12:34');
    });

    test('1시간 이상은 h:mm:ss', () {
      expect(formatDuration(const Duration(hours: 1)), '1:00:00');
      expect(
        formatDuration(const Duration(hours: 2, minutes: 3, seconds: 9)),
        '2:03:09',
      );
    });

    test('음수는 0으로 클램프', () {
      expect(formatDuration(const Duration(seconds: -10)), '00:00');
    });
  });
}
