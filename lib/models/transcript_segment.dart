import 'package:flutter/foundation.dart';

/// STT 결과를 자막 단위로 묶은 원본 전사 세그먼트(번역 전).
@immutable
class TranscriptSegment {
  const TranscriptSegment({
    required this.start,
    required this.end,
    required this.text,
    required this.languageCode,
  }) : assert(end >= start, 'end must be >= start');

  final Duration start;
  final Duration end;

  /// 전사 원문.
  final String text;

  /// 감지/지정된 언어 코드(BCP-47, 예: `en-US`).
  final String languageCode;

  TranscriptSegment copyWith({
    Duration? start,
    Duration? end,
    String? text,
    String? languageCode,
  }) {
    return TranscriptSegment(
      start: start ?? this.start,
      end: end ?? this.end,
      text: text ?? this.text,
      languageCode: languageCode ?? this.languageCode,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TranscriptSegment &&
          other.start == start &&
          other.end == end &&
          other.text == text &&
          other.languageCode == languageCode;

  @override
  int get hashCode => Object.hash(start, end, text, languageCode);

  @override
  String toString() =>
      'TranscriptSegment(${start.inMilliseconds}-${end.inMilliseconds}ms '
      '[$languageCode]: "$text")';
}

/// STT 단어 단위 타임스탬프. `enableWordTimeOffsets` 결과를 담는다.
@immutable
class TranscriptWord {
  const TranscriptWord({
    required this.start,
    required this.end,
    required this.word,
  });

  final Duration start;
  final Duration end;
  final String word;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TranscriptWord &&
          other.start == start &&
          other.end == end &&
          other.word == word;

  @override
  int get hashCode => Object.hash(start, end, word);

  @override
  String toString() => 'TranscriptWord("$word" '
      '${start.inMilliseconds}-${end.inMilliseconds}ms)';
}

/// STT 오프셋 문자열(`"1.300s"`)을 [Duration]으로 견고하게 파싱한다.
///
/// 허용 형식: `"1.300s"`, `"12s"`, `"0s"`, `1.3`(숫자), null/공백 -> [Duration.zero].
/// 음수·비정상 입력은 0으로 클램프한다(STT가 가끔 음수/누락 값을 줄 수 있음).
Duration parseSttDuration(Object? raw) {
  if (raw == null) return Duration.zero;
  double seconds;
  if (raw is num) {
    seconds = raw.toDouble();
  } else {
    final cleaned = raw.toString().trim().replaceAll('s', '');
    if (cleaned.isEmpty) return Duration.zero;
    seconds = double.tryParse(cleaned) ?? 0;
  }
  if (seconds.isNaN || seconds.isInfinite || seconds < 0) return Duration.zero;
  return Duration(
      microseconds: (seconds * Duration.microsecondsPerSecond).round());
}
