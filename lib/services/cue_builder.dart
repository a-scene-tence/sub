import '../models/subtitle_cue.dart';

/// 인접 큐의 종료 시각을 다음 큐 시작으로 클램프해 비중첩을 보장(순수 함수, 테스트 대상).
/// 입력은 시작 시각 기준 정렬되어 있다고 가정한다.
///
/// 캡션은 [GeminiCaptionService]가 윈도우 단위로 만들고, 누적 병합 시 이 함수로 겹침을 없앤다.
List<SubtitleCue> clampOverlaps(List<SubtitleCue> cues) {
  if (cues.length < 2) return List<SubtitleCue>.from(cues);
  final out = <SubtitleCue>[];
  for (var i = 0; i < cues.length; i++) {
    final cue = cues[i];
    if (i + 1 < cues.length) {
      final nextStart = cues[i + 1].start;
      if (cue.end > nextStart) {
        out.add(
            cue.copyWith(end: nextStart < cue.start ? cue.start : nextStart));
        continue;
      }
    }
    out.add(cue);
  }
  return out;
}
