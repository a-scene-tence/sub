import 'package:flutter_test/flutter_test.dart';
import 'package:video_subtitle_translator/widgets/gesture_math.dart';

void main() {
  group('gestureSideFromDx', () {
    test('중앙 왼쪽은 left, 중앙 이상은 right', () {
      expect(gestureSideFromDx(10, 100), GestureSide.left);
      expect(gestureSideFromDx(49.9, 100), GestureSide.left);
      expect(gestureSideFromDx(50, 100), GestureSide.right);
      expect(gestureSideFromDx(90, 100), GestureSide.right);
    });

    test('폭이 0 이하이면 left로 안전 처리', () {
      expect(gestureSideFromDx(10, 0), GestureSide.left);
      expect(gestureSideFromDx(10, -5), GestureSide.left);
    });
  });

  group('adjustLevel', () {
    test('위로 드래그(델타 음수)면 증가, 아래로면 감소', () {
      // height 200에서 -100 드래그 → +0.5.
      expect(adjustLevel(0.2, -100, 200), closeTo(0.7, 1e-9));
      expect(adjustLevel(0.8, 100, 200), closeTo(0.3, 1e-9));
    });

    test('0.0~1.0으로 클램프', () {
      expect(adjustLevel(0.9, -1000, 200), 1.0);
      expect(adjustLevel(0.1, 1000, 200), 0.0);
    });

    test('전체 높이만큼 위로 드래그하면 약 1.0 증가', () {
      expect(adjustLevel(0.0, -200, 200), closeTo(1.0, 1e-9));
    });

    test('height가 0 이하이면 현재값(클램프) 유지', () {
      expect(adjustLevel(0.4, -50, 0), 0.4);
      expect(adjustLevel(1.5, -50, -10), 1.0);
    });

    test('감도(sensitivity) 반영', () {
      expect(adjustLevel(0.0, -100, 200, sensitivity: 2.0), closeTo(1.0, 1e-9));
    });
  });

  group('seekTargetFor', () {
    const duration = Duration(minutes: 2); // 120s

    test('중간에서 +10초', () {
      expect(
        seekTargetFor(const Duration(seconds: 30), duration,
            const Duration(seconds: 10)),
        const Duration(seconds: 40),
      );
    });

    test('끝 근처에서 +10초는 duration으로 클램프', () {
      expect(
        seekTargetFor(const Duration(seconds: 115), duration,
            const Duration(seconds: 10)),
        duration,
      );
    });

    test('시작 근처에서 −10초는 0으로 클램프', () {
      expect(
        seekTargetFor(const Duration(seconds: 5), duration,
            const Duration(seconds: -10)),
        Duration.zero,
      );
    });

    test('정확히 경계값', () {
      expect(
        seekTargetFor(const Duration(seconds: 110), duration,
            const Duration(seconds: 10)),
        const Duration(seconds: 120),
      );
      expect(
        seekTargetFor(const Duration(seconds: 10), duration,
            const Duration(seconds: -10)),
        Duration.zero,
      );
    });
  });
}
