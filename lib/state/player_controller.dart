import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../engine/subtitle_sync_engine.dart';
import '../models/subtitle_cue.dart';

/// 비디오 재생과 자막 동기화를 묶는 컨트롤러.
///
/// `video_player`는 고빈도 위치 스트림이 없으므로 ~10Hz 타이머로 위치를 폴링하고,
/// 활성 자막이 바뀔 때만 [activeCue]를 갱신한다(불필요한 리빌드 방지).
class PlayerController {
  PlayerController({this.tick = const Duration(milliseconds: 100)});

  final Duration tick;

  VideoPlayerController? _video;
  SubtitleSyncEngine? _engine;
  Timer? _timer;

  /// 현재 표시할 자막. 없으면 null.
  final ValueNotifier<SubtitleCue?> activeCue =
      ValueNotifier<SubtitleCue?>(null);

  VideoPlayerController? get video => _video;

  /// 비디오 컨트롤러와 자막 큐를 설정하고 동기화 타이머를 시작한다.
  void attach(VideoPlayerController video, List<SubtitleCue> cues) {
    _video = video;
    _engine = SubtitleSyncEngine(cues);
    _start();
  }

  /// 자막 큐만 교체(언어 변경 등). 비디오는 유지.
  void updateCues(List<SubtitleCue> cues) {
    _engine = SubtitleSyncEngine(cues);
    _evaluate();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(tick, (_) => _evaluate());
  }

  void _evaluate() {
    final video = _video;
    final engine = _engine;
    if (video == null || engine == null) return;
    if (!video.value.isInitialized) return;
    final cue = engine.cueAt(video.value.position);
    if (cue != activeCue.value) activeCue.value = cue;
  }

  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    activeCue.dispose();
    await _video?.dispose();
    _video = null;
    _engine = null;
  }
}
