// 재생 제스처의 순수 계산 로직(플러그인/부수효과 없음 → 단위 테스트 대상).

import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

/// 탭/드래그가 레이어의 좌/우 절반 중 어디에 속하는지.
enum GestureSide { left, right }

/// x좌표 [dx]가 폭 [width]의 어느 절반인지 판정한다.
/// `dx < width/2`이면 left, 아니면 right. [width]가 0 이하이면 안전하게 left.
GestureSide gestureSideFromDx(double dx, double width) {
  if (width <= 0) return GestureSide.left;
  return dx < width / 2 ? GestureSide.left : GestureSide.right;
}

/// 세로 드래그 증분([primaryDelta])을 0.0~1.0 레벨 변화로 환산한다.
///
/// 위로 드래그하면 화면 y가 줄어 [primaryDelta]가 음수이므로, 부호를 뒤집어
/// "위=증가"가 되게 한다. 결과는 0.0~1.0으로 클램프. [height]가 0 이하이면 현재값 유지.
double adjustLevel(
  double current,
  double primaryDelta,
  double height, {
  double sensitivity = 1.0,
}) {
  if (height <= 0) return current.clamp(0.0, 1.0);
  final next = current + (-primaryDelta / height) * sensitivity;
  return next.clamp(0.0, 1.0);
}

/// 더블탭 탐색 목표 위치. `position+delta`를 0~[duration] 범위로 클램프한다.
Duration seekTargetFor(Duration position, Duration duration, Duration delta) {
  var target = position + delta;
  if (target < Duration.zero) target = Duration.zero;
  if (target > duration) target = duration;
  return target;
}

/// 가로 드래그 [dx]px를 탐색 시간으로 환산한다.
///
/// 화면 폭 [layerWidth]만큼 끝까지 드래그하면 [fullWidthSeek]만큼 이동(기본 ±90초).
/// 오른쪽(+dx)=앞으로, 왼쪽(−dx)=뒤로. [layerWidth]가 0 이하이면 0.
Duration seekDeltaForDrag(
  double dx,
  double layerWidth, {
  Duration fullWidthSeek = const Duration(seconds: 90),
}) {
  if (layerWidth <= 0) return Duration.zero;
  final ms = (dx / layerWidth) * fullWidthSeek.inMilliseconds;
  return Duration(milliseconds: ms.round());
}

/// 확대 비율을 [min]~[max]로 클램프한다(핀치 줌).
double clampScale(double scale, {double min = 1.0, double max = 3.0}) {
  if (scale.isNaN) return min;
  return scale.clamp(min, max);
}

/// 확대 상태에서 콘텐츠가 화면 밖으로 빠지지 않도록 팬 오프셋을 제한한다.
///
/// 중앙 정렬·[scale]배 확대 기준, 각 축으로 넘칠 수 있는 최대치는
/// `viewport*(scale-1)/2`이다. `scale<=1`이면 이동 불가(0으로 고정).
Offset clampOffset(Offset offset, double scale, Size viewport) {
  if (scale <= 1) return Offset.zero;
  final maxX = math.max(0.0, viewport.width * (scale - 1) / 2);
  final maxY = math.max(0.0, viewport.height * (scale - 1) / 2);
  return Offset(
    offset.dx.clamp(-maxX, maxX),
    offset.dy.clamp(-maxY, maxY),
  );
}
