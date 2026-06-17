import '../models/subtitle_cue.dart';

/// 재생 위치에 맞는 활성 자막을 선택하는 순수 로직.
///
/// 입력 큐 리스트는 **시작 시각 기준 정렬·비중첩**이어야 한다(생성은 `CueBuilder`).
/// `video_player`는 고빈도 위치 스트림을 제공하지 않으므로, 호출자가 타이머(~10Hz)로
/// 현재 위치를 폴링해 [cueAt]을 호출하고, 활성 큐가 바뀔 때만 UI를 갱신한다.
class SubtitleSyncEngine {
  SubtitleSyncEngine(List<SubtitleCue> cues, {this.offset = Duration.zero})
      : _cues = List<SubtitleCue>.unmodifiable(cues) {
    assert(_isSorted(_cues),
        'cues must be sorted by start time and non-overlapping');
  }

  final List<SubtitleCue> _cues;

  /// 표시 타이밍 보정 오프셋. 양수면 자막을 미리, 음수면 늦게 표시한다.
  /// (추출/디코더 지연으로 인한 드리프트를 튜닝).
  final Duration offset;

  /// 순방향 재생 빠른 경로용 캐시 인덱스.
  int _lastIndex = 0;

  List<SubtitleCue> get cues => _cues;

  /// [position] 시점의 활성 자막. 없으면 null(자막 미표시 구간).
  ///
  /// 이진 탐색이 정답 소스이며(되감기·시킹 정확), 직전 인덱스 캐시는 순방향
  /// 재생 시 탐색을 생략하는 최적화일 뿐이다.
  SubtitleCue? cueAt(Duration position) {
    if (_cues.isEmpty) return null;

    // offset이 양수면 자막을 미리 보여주기 위해 조회 위치를 뒤로 민다.
    final query = position - offset;

    // 빠른 경로: 직전에 반환한 큐가 여전히 활성인가?
    if (_lastIndex >= 0 && _lastIndex < _cues.length) {
      final cached = _cues[_lastIndex];
      if (cached.isActiveAt(query)) return cached;
    }

    final idx = _indexFor(query);
    _lastIndex = idx < 0 ? 0 : idx;
    if (idx < 0) return null;
    return _cues[idx];
  }

  /// [query]를 포함하는 큐의 인덱스. 없으면 -1.
  ///
  /// `start <= query`인 마지막 큐를 이진 탐색으로 찾고, 그 큐의 end 안인지 확인한다.
  int _indexFor(Duration query) {
    var lo = 0;
    var hi = _cues.length - 1;
    var candidate = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_cues[mid].start <= query) {
        candidate = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (candidate < 0) return -1; // query가 첫 큐 시작보다 이르다.
    return _cues[candidate].isActiveAt(query) ? candidate : -1; // gap이면 -1.
  }

  static bool _isSorted(List<SubtitleCue> cues) {
    for (var i = 1; i < cues.length; i++) {
      if (cues[i].start < cues[i - 1].start) return false;
      if (cues[i].start < cues[i - 1].end) return false; // 중첩 금지.
    }
    return true;
  }
}
