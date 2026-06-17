import 'package:characters/characters.dart';

import '../config/app_config.dart';
import '../models/recognition_result.dart';
import '../models/subtitle_cue.dart';
import '../models/transcript_segment.dart';
import 'translation_service.dart';

/// STT 결과(단어 단위 세그먼트)를 읽기 좋은 자막 큐로 묶고 번역해 [SubtitleCue] 목록을 만든다.
///
/// 순서: 단어 그룹화 -> 번역(배치) -> 중첩 클램프. 그룹화/클램프는 순수 로직으로 테스트 가능.
class CueBuilder {
  CueBuilder(this._translation);

  final TranslationService _translation;

  /// [recognition]을 [targetLanguage]로 번역한 자막 큐 리스트를 만든다.
  Future<List<SubtitleCue>> build(
    RecognitionResult recognition, {
    required String targetLanguage,
  }) async {
    if (recognition.isEmpty) return <SubtitleCue>[];

    final grouped = groupSegments(recognition.segments);
    if (grouped.isEmpty) return <SubtitleCue>[];

    final sourceTexts = grouped.map((s) => s.text).toList();
    final translated = await _translation.translateBatch(
      sourceTexts,
      target: targetLanguage,
      source: recognition.detectedLanguageCode.isEmpty
          ? null
          : recognition.detectedLanguageCode,
    );

    final cues = <SubtitleCue>[];
    for (var i = 0; i < grouped.length; i++) {
      final seg = grouped[i];
      cues.add(SubtitleCue(
        start: seg.start,
        end: seg.end,
        text: i < translated.length ? translated[i] : seg.text,
        sourceText: seg.text,
        languageCode: seg.languageCode,
      ));
    }
    return clampOverlaps(cues);
  }
}

/// 단어 단위 세그먼트를 자막 단위로 묶는다(순수 함수, 테스트 대상).
///
/// 분리 기준: 단어 간 간격 > [AppConfig.segmentSplitGap],
/// 누적 길이 > [AppConfig.maxSegmentChars], 누적 시간 > [AppConfig.maxSegmentDuration],
/// 또는 직전 단어가 종결 문장부호(. ? ! 。 ？ ！)로 끝남.
List<TranscriptSegment> groupSegments(List<TranscriptSegment> words) {
  if (words.isEmpty) return <TranscriptSegment>[];

  // 타임스탬프가 없는(0~0) 단일 fallback 세그먼트는 그대로 둔다.
  if (words.length == 1 && words.first.start == words.first.end) {
    return List<TranscriptSegment>.from(words);
  }

  final out = <TranscriptSegment>[];
  var bufWords = <String>[];
  Duration? bufStart;
  Duration bufEnd = Duration.zero;
  String lang = 'und';
  Duration? prevWordEnd;

  void flush() {
    if (bufWords.isEmpty || bufStart == null) return;
    out.add(TranscriptSegment(
      start: bufStart!,
      end: bufEnd < bufStart! ? bufStart! : bufEnd,
      text: bufWords.join(' '),
      languageCode: lang,
    ));
    bufWords = <String>[];
    bufStart = null;
    prevWordEnd = null;
  }

  for (final w in words) {
    final gap = (prevWordEnd == null) ? Duration.zero : w.start - prevWordEnd!;
    final prospectiveChars =
        bufWords.fold<int>(0, (a, s) => a + s.length + 1) + w.text.length;
    final prospectiveDuration =
        (bufStart == null) ? Duration.zero : w.end - bufStart!;

    final mustSplit = bufWords.isNotEmpty &&
        (gap > AppConfig.segmentSplitGap ||
            prospectiveChars > AppConfig.maxSegmentChars ||
            prospectiveDuration > AppConfig.maxSegmentDuration);

    if (mustSplit) flush();

    bufStart ??= w.start;
    bufWords.add(w.text);
    bufEnd = w.end;
    if (w.languageCode != 'und') lang = w.languageCode;
    prevWordEnd = w.end;

    if (_endsSentence(w.text)) flush();
  }
  flush();
  return out;
}

bool _endsSentence(String word) {
  if (word.isEmpty) return false;
  const enders = <String>{'.', '?', '!', '。', '？', '！', '…'};
  return enders.contains(word.characters.last);
}

/// 인접 큐의 종료 시각을 다음 큐 시작으로 클램프해 비중첩을 보장(순수 함수, 테스트 대상).
/// 입력은 시작 시각 기준 정렬되어 있다고 가정한다.
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
