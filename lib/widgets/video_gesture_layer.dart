import 'dart:async';

import 'package:flutter/material.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:video_player/video_player.dart';
import 'package:volume_controller/volume_controller.dart';

import 'gesture_math.dart';

/// 영상 영역 위에 깔리는 투명 제스처 레이어.
///
/// 왼쪽 세로 드래그=화면 밝기, 오른쪽 세로 드래그=시스템 볼륨, 오른쪽 더블탭=+10초,
/// 왼쪽 더블탭=−10초. 밝기/볼륨 조절 시 작은 HUD를 잠깐 표시한다. 하단 컨트롤바는 별도
/// 위젯이라 이 레이어가 덮지 않는다(영상 영역만 덮음).
class VideoGestureLayer extends StatefulWidget {
  const VideoGestureLayer({super.key, required this.controller});

  final VideoPlayerController controller;

  @override
  State<VideoGestureLayer> createState() => _VideoGestureLayerState();
}

enum _HudKind { brightness, volume }

class _VideoGestureLayerState extends State<VideoGestureLayer> {
  static const Duration _seekStep = Duration(seconds: 10);

  final ScreenBrightness _brightnessCtl = ScreenBrightness();
  final VolumeController _volumeCtl = VolumeController();

  double _brightness = 0.5; // 0..1, initState에서 실제값으로 교체.
  double _volume = 0.5;

  GestureSide? _dragSide; // 드래그 시작 시 고정.
  GestureSide _lastTapSide = GestureSide.left; // onDoubleTapDown에서 기록.
  double _layerWidth = 0;
  double _layerHeight = 0;

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

  void _onVerticalDragStart(DragStartDetails d) {
    _dragSide = gestureSideFromDx(d.localPosition.dx, _layerWidth);
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    final dy = d.primaryDelta ?? 0;
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

  void _onVerticalDragEnd(DragEndDetails d) => _dragSide = null;

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
          onDoubleTapDown: _onDoubleTapDown,
          onDoubleTap: _onDoubleTap,
          onVerticalDragStart: _onVerticalDragStart,
          onVerticalDragUpdate: _onVerticalDragUpdate,
          onVerticalDragEnd: _onVerticalDragEnd,
          child: Stack(
            children: <Widget>[
              const Positioned.fill(child: SizedBox.expand()),
              if (_hudKind != null)
                Center(child: _Hud(kind: _hudKind!, level: _hudLevel)),
            ],
          ),
        );
      },
    );
  }
}

/// 밝기/볼륨 조절 중 표시되는 작은 HUD(아이콘 + 퍼센트).
class _Hud extends StatelessWidget {
  const _Hud({required this.kind, required this.level});

  final _HudKind kind;
  final double level;

  @override
  Widget build(BuildContext context) {
    final icon =
        kind == _HudKind.brightness ? Icons.brightness_6 : Icons.volume_up;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Text(
            '${(level * 100).round()}%',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
