import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../config/app_config.dart';
import '../models/subtitle_cue.dart';
import '../services/audio_extraction_service.dart';
import '../services/cue_builder.dart';
import '../services/diagnostics.dart';
import '../services/speech_service.dart';
import 'player_controller.dart';

/// 라이브 자막 진행 상태(전체화면 차단 오버레이 대신 가벼운 표식용).
enum LiveStatus { idle, working, error }

@immutable
class LiveCaptionState {
  const LiveCaptionState({this.status = LiveStatus.idle, this.errorMessage});

  final LiveStatus status;
  final String? errorMessage;

  LiveCaptionState copyWith({LiveStatus? status, String? errorMessage}) =>
      LiveCaptionState(
        status: status ?? this.status,
        errorMessage: errorMessage,
      );
}

/// 재생 중 보고 있는 구간만 실시간으로 인식·번역해 자막을 점진적으로 붙이는 컨트롤러.
///
/// 영상 전체를 미리 처리하지 않는다. [enabled]이고 재생 중일 때만, 재생 위치를 따라
/// 다음 윈도우 `[_processedEnd, _processedEnd+window)`를 네이티브로 추출 → 동기 STT
/// (윈도우 < 60초) → [CueBuilder]로 번역·큐 생성 → 시각을 윈도우 시작만큼 밀어 누적
/// 목록에 병합 → [PlayerController.updateCues]로 갱신한다.
///
/// API 절감: 재생을 따라가며 본 구간만 호출한다. 앞으로 탐색하면 건너뛴 구간은
/// 인식하지 않고(frontier 점프), 뒤로 탐색하면 캐시된 큐를 그대로 재사용한다.
class LiveCaptionController extends ValueNotifier<LiveCaptionState> {
  LiveCaptionController({
    required AudioExtractor extractor,
    required SpeechService speech,
    required CueBuilder cueBuilder,
    required String videoPath,
    required this.targetLanguage,
    this.languageHint,
    Duration? window,
    Duration? lookahead,
    Duration tick = const Duration(milliseconds: 500),
  })  : _extractor = extractor,
        _speech = speech,
        _cueBuilder = cueBuilder,
        _videoPath = videoPath,
        _window = window ?? AppConfig.liveWindow,
        _lookahead = lookahead ?? AppConfig.liveLookahead,
        _tick = tick,
        super(const LiveCaptionState());

  final AudioExtractor _extractor;
  final SpeechService _speech;
  final CueBuilder _cueBuilder;
  final String _videoPath;
  final String targetLanguage;
  final String? languageHint;
  final Duration _window;
  final Duration _lookahead;
  final Duration _tick;

  VideoPlayerController? _video;
  PlayerController? _player;
  Timer? _timer;

  /// 설정과 동기화되는 ON/OFF 플래그. 화면에서 매 빌드마다 대입(멱등).
  bool enabled = false;

  bool _busy = false; // 단일 비행 가드(동시 추출 방지).
  bool _disposed = false;

  /// 이미 인식·번역을 마친 frontier(영상 시각). 여기서부터 다음 윈도우를 만든다.
  Duration _processedEnd = Duration.zero;

  /// 누적 자막(시작 시각 정렬·비중첩). 매 윈도우마다 병합 후 플레이어에 전달한다.
  final List<SubtitleCue> _cues = <SubtitleCue>[];

  /// 현재까지 생성된 자막(읽기 전용).
  List<SubtitleCue> get cues => List<SubtitleCue>.unmodifiable(_cues);

  /// 비디오/플레이어를 연결하고 tick 타이머를 시작한다. 자막 동기화는 [player]가 담당.
  void attach(VideoPlayerController video, PlayerController player) {
    _bind(video, player);
    _timer?.cancel();
    _timer = Timer.periodic(_tick, (_) => _onTick());
  }

  /// 테스트용: 타이머 없이 비디오/플레이어만 연결한다(스텝은 [stepOnce]로 구동).
  @visibleForTesting
  void bindForTest(VideoPlayerController video, PlayerController player) =>
      _bind(video, player);

  void _bind(VideoPlayerController video, PlayerController player) {
    _video = video;
    _player = player;
  }

  void _onTick() {
    final next = _planNext();
    if (next == null) return;
    _busy = true;
    _setStatus(LiveStatus.working);
    // 타이머 콜백을 막지 않도록 await하지 않는다(_busy로 다음 tick 중복 방지).
    unawaited(_step(next.start, next.end));
  }

  /// 처리할 다음 윈도우를 정한다. 자격이 없으면 null. 앞으로 탐색 시 frontier를
  /// 재생 위치로 점프시키는 부수효과가 있다(건너뛴 구간은 인식하지 않음).
  ({Duration start, Duration end})? _planNext() {
    if (!enabled || _busy) return null;
    final v = _video;
    if (v == null || !v.value.isInitialized || !v.value.isPlaying) return null;

    final pos = v.value.position;
    final duration = v.value.duration;

    // 앞으로 크게 탐색해 미처리 구간에 진입하면 frontier를 재생 위치로 점프
    // (건너뛴 구간은 추출하지 않아 API 절약).
    if (pos > _processedEnd + _window) _processedEnd = pos;

    // 재생보다 충분히 앞서 처리해 뒀으면 대기(불필요한 선행 처리 방지).
    if (_processedEnd > pos + _lookahead) return null;
    if (_processedEnd >= duration) return null;

    final start = _processedEnd;
    var end = start + _window;
    if (end > duration) end = duration;
    if (end <= start) return null;
    return (start: start, end: end);
  }

  Future<void> _step(Duration start, Duration end) async {
    File? wav;
    try {
      wav = await _extractor.extractWav(_videoPath, start: start, end: end);
      final bytes = await wav.readAsBytes(); // 윈도우(≤15초)는 작아 전체 읽기 안전.
      final rec = await _speech.recognize(bytes, languageHint: languageHint);
      if (!rec.isEmpty) {
        final cues =
            await _cueBuilder.build(rec, targetLanguage: targetLanguage);
        final shifted = cues
            .map((c) => c.copyWith(start: c.start + start, end: c.end + start))
            .toList();
        _mergeCues(shifted, windowStart: start);
        _player?.updateCues(List<SubtitleCue>.of(_cues));
      }
      _processedEnd = end; // 무음이어도 frontier 전진(같은 구간 재호출 방지).
      _setStatus(LiveStatus.idle);
    } catch (e) {
      await Diagnostics.record('live: 윈도우 처리 실패: $e');
      // frontier 유지 → 다음 tick에서 같은 구간 재시도.
      _setStatus(LiveStatus.error, message: e.toString());
    } finally {
      if (wav != null) await _extractor.cleanup(wav);
      _busy = false;
    }
  }

  /// 새 큐를 누적 목록에 병합한다. 윈도우 경계의 pre-roll 중복을 막기 위해 윈도우
  /// 시작 이전에서 시작하는 큐는 버리고, 정렬 후 [clampOverlaps]로 비중첩을 보장한다.
  void _mergeCues(List<SubtitleCue> incoming, {required Duration windowStart}) {
    for (final c in incoming) {
      if (c.start >= windowStart) _cues.add(c);
    }
    _cues.sort((a, b) => a.start.compareTo(b.start));
    final clamped = clampOverlaps(_cues);
    _cues
      ..clear()
      ..addAll(clamped);
  }

  void _setStatus(LiveStatus status, {String? message}) {
    if (_disposed) return;
    value = value.copyWith(status: status, errorMessage: message);
  }

  /// 테스트용: 타이머 없이 한 스텝을 평가/실행한다. enabled·재생 중일 때 동작.
  @visibleForTesting
  Future<void> stepOnce() async {
    final next = _planNext();
    if (next == null) return;
    _busy = true;
    _setStatus(LiveStatus.working);
    await _step(next.start, next.end);
  }

  @visibleForTesting
  Duration get processedEnd => _processedEnd;

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _video = null;
    _player = null;
    super.dispose();
  }
}
