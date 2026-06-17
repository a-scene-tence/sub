import 'package:flutter/foundation.dart';

import 'transcript_segment.dart';

/// STT 전체 결과: 감지된 대표 언어 + 자막 세그먼트 목록.
@immutable
class RecognitionResult {
  const RecognitionResult({
    required this.segments,
    required this.detectedLanguageCode,
  });

  final List<TranscriptSegment> segments;

  /// 전체에서 가장 많이 감지된 언어 코드(BCP-47). 음성이 없으면 빈 문자열.
  final String detectedLanguageCode;

  bool get isEmpty => segments.isEmpty;

  static const RecognitionResult empty = RecognitionResult(
    segments: <TranscriptSegment>[],
    detectedLanguageCode: '',
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecognitionResult &&
          listEquals(other.segments, segments) &&
          other.detectedLanguageCode == detectedLanguageCode;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(segments), detectedLanguageCode);

  @override
  String toString() =>
      'RecognitionResult($detectedLanguageCode, ${segments.length} segments)';
}
