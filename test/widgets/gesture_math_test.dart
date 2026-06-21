import 'dart:ui';

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

  group('seekDeltaForDrag', () {
    test('폭 끝까지(+)는 기본 +90초, 절반은 +45초', () {
      expect(seekDeltaForDrag(400, 400), const Duration(seconds: 90));
      expect(seekDeltaForDrag(200, 400), const Duration(seconds: 45));
    });

    test('왼쪽(음수)은 뒤로 이동', () {
      expect(seekDeltaForDrag(-400, 400), const Duration(seconds: -90));
      expect(seekDeltaForDrag(-100, 400), const Duration(milliseconds: -22500));
    });

    test('fullWidthSeek 사용자 지정', () {
      expect(
        seekDeltaForDrag(400, 400, fullWidthSeek: const Duration(seconds: 30)),
        const Duration(seconds: 30),
      );
    });

    test('layerWidth가 0 이하이면 0', () {
      expect(seekDeltaForDrag(100, 0), Duration.zero);
      expect(seekDeltaForDrag(100, -5), Duration.zero);
    });
  });

  group('clampScale', () {
    test('범위 1.0~3.0으로 클램프', () {
      expect(clampScale(0.5), 1.0);
      expect(clampScale(2.0), 2.0);
      expect(clampScale(5.0), 3.0);
    });
    test('NaN은 최소값', () {
      expect(clampScale(double.nan), 1.0);
    });
    test('사용자 지정 범위', () {
      expect(clampScale(10, max: 4.0), 4.0);
    });
  });

  group('clampOffset', () {
    const viewport = Size(400, 300);

    test('scale<=1이면 이동 불가(0 고정)', () {
      expect(clampOffset(const Offset(50, 50), 1.0, viewport), Offset.zero);
      expect(clampOffset(const Offset(50, 50), 0.5, viewport), Offset.zero);
    });

    test('확대 시 ±(viewport*(scale-1)/2)로 클램프', () {
      // scale 2.0 → maxX=400*1/2=200, maxY=300*1/2=150.
      expect(clampOffset(const Offset(500, 500), 2.0, viewport),
          const Offset(200, 150));
      expect(clampOffset(const Offset(-500, -500), 2.0, viewport),
          const Offset(-200, -150));
      // 범위 안은 그대로.
      expect(clampOffset(const Offset(100, 100), 2.0, viewport),
          const Offset(100, 100));
    });
  });
}
