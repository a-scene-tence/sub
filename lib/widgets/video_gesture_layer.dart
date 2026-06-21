import 'dart:async';

import 'package:flutter/material.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:video_player/video_player.dart';
import 'package:volume_controller/volume_controller.dart';

import 'gesture_math.dart';
import 'player_controls.dart' show formatDuration;

/// 영상 영역 위에 깔리는 투명 제스처 레이어.
///
/// 한 손가락 드래그: 시작 직후 주축을 잠가, **가로=탐색(끝까지 ±90초, 실시간 이동)**,
/// 세로=화면 밝기(왼쪽)/시스템 볼륨(오른쪽). 더블탭=시크(오른쪽 +10초, 왼쪽 −10초).
/// [zoomEnabled]이면 두 손가락 핀치=확대/축소, 두 손가락 이동=팬. 조절 중 작은 HUD를 잠깐
/// 표시한다. 하단 컨트롤바는 별도 위젯이라 이 레이어가 덮지 않는다.
///
/// 한 `GestureDetector`에서 세로 드래그와 스케일을 동시에 못 쓰므로, 모든 드래그를 `onScale*`에서
/// 처리한다(2손가락=줌/팬, 1손가락=첫 이동에서 가로/세로 주축을 잠가 탐색 또는 밝기·볼륨).
class VideoGestureLayer extends StatefulWidget {
  const VideoGestureLayer({
    super.key,
    required this.controller,
    this.zoomEnabled = false,
    this.scale = 1.0,
    this.offset = Offset.zero,
    this.onZoomChanged,
    this.onTap,
  });

  final VideoPlayerController controller;
  final bool zoomEnabled;
  final double scale;
  final Offset offset;
  final void Function(double scale, Offset offset)? onZoomChanged;

  /// 한 번 탭(더블탭과 구분됨): 재생 컨트롤 표시/숨김 토글에 사용.
  final VoidCallback? onTap;

  @override
  State<VideoGestureLayer> createState() => _VideoGestureLayerState();
}

enum _HudKind { brightness, volume, seek }

/// 한 손가락 드래그의 주축. 첫 유의미한 이동에서 [horizontal]/[vertical]로 잠긴다.
enum _DragAxis { undecided, horizontal, vertical }

class _VideoGestureLayerState extends State<VideoGestureLayer> {
  static const Duration _seekStep = Duration(seconds: 10);

  /// 주축을 결정하기 위한 최소 이동 거리(px).
  static const double _axisLockThreshold = 8.0;

  final ScreenBrightness _brightnessCtl = ScreenBrightness();
  final VolumeController _volumeCtl = VolumeController();

  double _brightness = 0.5; // 0..1, initState에서 실제값으로 교체.
  double _volume = 0.5;

  GestureSide? _dragSide; // 드래그 시작 시 고정.
  GestureSide _lastTapSide = GestureSide.left; // onDoubleTapDown에서 기록.
  double _layerWidth = 0;
  double _layerHeight = 0;

  // 스케일 제스처 시작 시점의 기준값(핀치 줌/팬 누적용).
  double _baseScale = 1.0;
  Offset _baseOffset = Offset.zero;
  Offset _startFocal = Offset.zero;

  // 한 손가락 드래그 주축 잠금 + 가로 탐색 상태.
  _DragAxis _axis = _DragAxis.undecided;
  Duration _seekStartPos = Duration.zero; // 드래그 시작 시 재생 위치.
  Duration _seekTarget = Duration.zero; // 탐색 HUD 표시용 목표 위치.
  Duration _seekDuration = Duration.zero; // 탐색 HUD 표시용 총 길이.

  _HudKind? _hudKind;
  double _hudLevel = 0;
  Timer? _hudTimer;

  @override
  void initState() {
    super.initState();
    // 시스템 볼륨 기본 HUD 억제(우리 HUD만 표시).
    _volumeCtl.showSystemUI = false;
    _initLevels();
  }

  Future<void> _initLevels() async {
    try {
      final b = await _brightnessCtl.current;
      if (mounted) setState(() => _brightness = b);
    } catch (_) {/* 기본값 유지 */}
    try {
      final v = await _volumeCtl.getVolume();
      if (mounted) setState(() => _volume = v);
    } catch (_) {/* 기본값 유지 */}
  }

  void _showHud(_HudKind kind, double level) {
    setState(() {
      _hudKind = kind;
      _hudLevel = level;
    });
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _hudKind = null);
    });
  }

  void _onDoubleTapDown(TapDownDetails d) {
    _lastTapSide = gestureSideFromDx(d.localPosition.dx, _layerWidth);
  }

  void _onDoubleTap() {
    final delta = _lastTapSide == GestureSide.right ? _seekStep : -_seekStep;
    final v = widget.controller.value;
    if (!v.isInitialized) return;
    widget.controller.seekTo(seekTargetFor(v.position, v.duration, delta));
  }

  void _onScaleStart(ScaleStartDetails d) {
    _dragSide = gestureSideFromDx(d.localFocalPoint.dx, _layerWidth);
    _baseScale = widget.scale;
    _baseOffset = widget.offset;
    _startFocal = d.localFocalPoint;
    _axis = _DragAxis.undecided;
    _seekStartPos = widget.controller.value.position;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount >= 2) {
      // 두 손가락: 핀치 줌 + 팬(전체화면에서만).
      if (!widget.zoomEnabled) return;
      final newScale = clampScale(_baseScale * d.scale);
      final moved = _baseOffset + (d.localFocalPoint - _startFocal);
      final newOffset =
          clampOffset(moved, newScale, Size(_layerWidth, _layerHeight));
      widget.onZoomChanged?.call(newScale, newOffset);
      return;
    }

    // 한 손가락: 첫 유의미한 이동에서 주축(가로=탐색/세로=밝기·볼륨)을 잠근다.
    final total = d.localFocalPoint - _startFocal;
    if (_axis == _DragAxis.undecided) {
      if (total.distance < _axisLockThreshold) return; // 아직 의도 불명확.
      _axis = total.dx.abs() > total.dy.abs()
          ? _DragAxis.horizontal
          : _DragAxis.vertical;
    }

    if (_axis == _DragAxis.horizontal) {
      // 가로: 시작 위치 기준 절대 탐색(드래그 따라 실시간 이동).
      final v = widget.controller.value;
      if (!v.isInitialized) return;
      final target =
          seekTargetFor(_seekStartPos, v.duration, seekDeltaForDrag(total.dx, _layerWidth));
      widget.controller.seekTo(target);
      _seekTarget = target;
      _seekDuration = v.duration;
      _showHud(_HudKind.seek, 0);
      return;
    }

    // 세로: 밝기(왼쪽)/볼륨(오른쪽).
    final dy = d.focalPointDelta.dy;
    if (_dragSide == GestureSide.left) {
      _brightness = adjustLevel(_brightness, dy, _layerHeight);
      _brightnessCtl.setScreenBrightness(_brightness);
      _showHud(_HudKind.brightness, _brightness);
    } else {
      _volume = adjustLevel(_volume, dy, _layerHeight);
      _volumeCtl.setVolume(_volume);
      _showHud(_HudKind.volume, _volume);
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    _dragSide = null;
    _axis = _DragAxis.undecided;
  }

  @override
  void dispose() {
    _hudTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _layerWidth = constraints.maxWidth;
        _layerHeight = constraints.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onDoubleTapDown: _onDoubleTapDown,
          onDoubleTap: _onDoubleTap,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          child: Stack(
            children: <Widget>[
              const Positioned.fill(child: SizedBox.expand()),
              if (_hudKind != null)
                Center(
                  child: _Hud(
                    kind: _hudKind!,
                    level: _hudLevel,
                    seekTarget: _seekTarget,
                    seekDuration: _seekDuration,
                    seekDelta: _seekTarget - _seekStartPos,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 밝기/볼륨/탐색 조절 중 표시되는 작은 HUD.
/// 밝기·볼륨은 아이콘 + 퍼센트, 탐색은 `목표/총시간 (±오프셋)`을 보여준다.
class _Hud extends StatelessWidget {
  const _Hud({
    required this.kind,
    required this.level,
    this.seekTarget = Duration.zero,
    this.seekDuration = Duration.zero,
    this.seekDelta = Duration.zero,
  });

  final _HudKind kind;
  final double level;
  final Duration seekTarget;
  final Duration seekDuration;
  final Duration seekDelta;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: kind == _HudKind.seek ? _buildSeek() : _buildLevel(),
    );
  }

  Widget _buildLevel() {
    final icon =
        kind == _HudKind.brightness ? Icons.brightness_6 : Icons.volume_up;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: 8),
        Text(
          '${(level * 100).round()}%',
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildSeek() {
    final forward = !seekDelta.isNegative;
    final sign = forward ? '+' : '−';
    final absDelta = seekDelta.abs();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(forward ? Icons.fast_forward : Icons.fast_rewind,
            color: Colors.white, size: 20),
        const SizedBox(width: 8),
        Text(
          '${formatDuration(seekTarget)} / ${formatDuration(seekDuration)}'
          '  ($sign${formatDuration(absDelta)})',
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ],
    );
  }
}
