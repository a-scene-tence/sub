import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../providers.dart';

/// [Duration]을 `mm:ss`(1시간 미만) 또는 `h:mm:ss`로 포맷한다(순수 함수, 테스트 대상).
String formatDuration(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$mm:$ss';
  return '$mm:$ss';
}

/// 재생 컨트롤바: 실시간 번역 토글 + play/pause + 탐색 슬라이더 + 시간 라벨.
///
/// [VideoPlayerController]는 자체가 `ValueListenable<VideoPlayerValue>`라 그것을 구독해
/// 위치/길이/재생상태를 그린다. 드래그 중에는 로컬값으로 표시하고 손을 뗄 때 `seekTo`한다.
/// 실시간 번역 토글은 [settingsProvider]를 읽고 써서 설정 화면과 항상 동기화된다.
class PlayerControls extends ConsumerStatefulWidget {
  const PlayerControls({
    super.key,
    required this.controller,
    required this.isFullscreen,
    required this.onToggleFullscreen,
    required this.isFill,
    required this.onToggleFill,
  });

  final VideoPlayerController controller;
  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;
  final bool isFill;
  final VoidCallback onToggleFill;

  @override
  ConsumerState<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends ConsumerState<PlayerControls> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final liveOn = settings.value.liveTranslateEnabled;

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final duration = value.duration;
        final totalMs = duration.inMilliseconds;
        final positionMs =
            value.position.inMilliseconds.clamp(0, totalMs).toDouble();
        final sliderValue = _dragValue ?? positionMs;
        final shown = _dragValue != null
            ? Duration(milliseconds: _dragValue!.round())
            : value.position;

        return Container(
          color: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: <Widget>[
              IconButton(
                icon: Icon(
                  liveOn ? Icons.subtitles : Icons.subtitles_off,
                  color: liveOn ? Colors.lightBlueAccent : Colors.white,
                ),
                tooltip: liveOn ? '실시간 자막 끄기' : '실시간 자막 켜기',
                onPressed: () =>
                    settings.setLiveTranslateEnabled(!liveOn),
              ),
              IconButton(
                icon: Icon(
                  value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
                onPressed: () => value.isPlaying
                    ? widget.controller.pause()
                    : widget.controller.play(),
              ),
              Text(
                formatDuration(shown),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              Expanded(
                child: Slider(
                  value: totalMs == 0
                      ? 0
                      : sliderValue.clamp(0, totalMs.toDouble()),
                  max: totalMs == 0 ? 1 : totalMs.toDouble(),
                  onChanged: totalMs == 0
                      ? null
                      : (v) => setState(() => _dragValue = v),
                  onChangeEnd: totalMs == 0
                      ? null
                      : (v) {
                          widget.controller
                              .seekTo(Duration(milliseconds: v.round()));
                          setState(() => _dragValue = null);
                        },
                ),
              ),
              Text(
                formatDuration(duration),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              // 비율 전환(맞춤 ↔ 꽉 채움)은 일반·전체화면 모두에서 노출.
              IconButton(
                icon: Icon(
                  widget.isFill ? Icons.fit_screen : Icons.aspect_ratio,
                  color: Colors.white,
                ),
                tooltip: widget.isFill ? '화면 맞춤' : '꽉 채움',
                onPressed: widget.onToggleFill,
              ),
              IconButton(
                icon: Icon(
                  widget.isFullscreen
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen,
                  color: Colors.white,
                ),
                tooltip: widget.isFullscreen ? '전체화면 종료' : '전체화면',
                onPressed: widget.onToggleFullscreen,
              ),
            ],
          ),
        );
      },
    );
  }
}
