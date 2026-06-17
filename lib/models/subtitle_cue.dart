import 'package:flutter/foundation.dart';

/// 화면에 표시되는 단위 자막. [start] ~ [end] 구간 동안 [text](번역문)를 노출한다.
///
/// 큐 리스트는 시간순 정렬·비중첩을 보장한다(생성은 `CueBuilder`가 담당).
@immutable
class SubtitleCue {
  const SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
    this.sourceText,
    this.languageCode,
  }) : assert(end >= start, 'end must be >= start');

  /// 자막 시작 시각(영상 기준).
  final Duration start;

  /// 자막 종료 시각(영상 기준).
  final Duration end;

  /// 표시할 번역문.
  final String text;

  /// 번역 전 원문(선택). 디버깅·원문 토글용.
  final String? sourceText;

  /// 감지된 원본 언어 코드(예: `en-US`).
  final String? languageCode;

  Duration get duration => end - start;

  /// [position]이 이 큐의 활성 구간 안인지 여부.
  /// 시작은 포함, 종료는 제외(`start <= position < end`)하여 인접 큐 경계 중복을 막는다.
  bool isActiveAt(Duration position) => position >= start && position < end;

  SubtitleCue copyWith({
    Duration? start,
    Duration? end,
    String? text,
    String? sourceText,
    String? languageCode,
  }) {
    return SubtitleCue(
      start: start ?? this.start,
      end: end ?? this.end,
      text: text ?? this.text,
      sourceText: sourceText ?? this.sourceText,
      languageCode: languageCode ?? this.languageCode,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubtitleCue &&
          other.start == start &&
          other.end == end &&
          other.text == text &&
          other.sourceText == sourceText &&
          other.languageCode == languageCode;

  @override
  int get hashCode => Object.hash(start, end, text, sourceText, languageCode);

  @override
  String toString() =>
      'SubtitleCue(${start.inMilliseconds}-${end.inMilliseconds}ms: "$text")';
}
