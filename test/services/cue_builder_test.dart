import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:video_subtitle_translator/models/recognition_result.dart';
import 'package:video_subtitle_translator/models/subtitle_cue.dart';
import 'package:video_subtitle_translator/models/transcript_segment.dart';
import 'package:video_subtitle_translator/services/cue_builder.dart';
import 'package:video_subtitle_translator/services/translation_service.dart';

class _MockTranslation extends Mock implements TranslationService {}

TranscriptSegment word(int startMs, int endMs, String text,
        {String lang = 'en-US'}) =>
    TranscriptSegment(
      start: Duration(milliseconds: startMs),
      end: Duration(milliseconds: endMs),
      text: text,
      languageCode: lang,
    );

void main() {
  group('groupSegments', () {
    test('빈 입력', () {
      expect(groupSegments(const <TranscriptSegment>[]), isEmpty);
    });

    test('큰 간격에서 분리', () {
      final words = <TranscriptSegment>[
        word(0, 300, 'hello'),
        word(350, 600, 'world'), // 간격 작음 -> 같은 세그먼트
        word(2000, 2300, 'again'), // 1400ms 간격 -> 분리
      ];
      final segs = groupSegments(words);
      expect(segs.length, 2);
      expect(segs[0].text, 'hello world');
      expect(segs[1].text, 'again');
      expect(segs[0].start, Duration.zero);
      expect(segs[0].end, const Duration(milliseconds: 600));
    });

    test('종결 문장부호에서 분리', () {
      final words = <TranscriptSegment>[
        word(0, 300, 'Hi.'),
        word(310, 600, 'Bye'),
      ];
      final segs = groupSegments(words);
      expect(segs.length, 2);
      expect(segs[0].text, 'Hi.');
      expect(segs[1].text, 'Bye');
    });

    test('타임스탬프 없는 단일 fallback 세그먼트는 그대로', () {
      final words = <TranscriptSegment>[word(0, 0, 'full transcript text')];
      final segs = groupSegments(words);
      expect(segs.length, 1);
      expect(segs[0].text, 'full transcript text');
    });
  });

  group('clampOverlaps', () {
    SubtitleCue cue(int s, int e) => SubtitleCue(
          start: Duration(milliseconds: s),
          end: Duration(milliseconds: e),
          text: 't',
        );

    test('중첩 큐의 end를 다음 start로 클램프', () {
      final result = clampOverlaps(<SubtitleCue>[
        cue(0, 1500),
        cue(1000, 2000),
      ]);
      expect(result[0].end, const Duration(milliseconds: 1000));
      expect(result[1].end, const Duration(milliseconds: 2000));
    });

    test('비중첩은 변화 없음', () {
      final input = <SubtitleCue>[cue(0, 1000), cue(1000, 2000)];
      expect(clampOverlaps(input), input);
    });

    test('클램프 후 동기화 엔진 불변식(비중첩) 만족', () {
      final result = clampOverlaps(<SubtitleCue>[
        cue(0, 1500),
        cue(1000, 2000),
        cue(1800, 3000),
      ]);
      for (var i = 1; i < result.length; i++) {
        expect(result[i].start >= result[i - 1].end, isTrue);
      }
    });
  });

  group('CueBuilder.build', () {
    late _MockTranslation translation;

    setUp(() {
      translation = _MockTranslation();
    });

    test('빈 인식 결과는 빈 큐', () async {
      final builder = CueBuilder(translation);
      final cues = await builder.build(
        RecognitionResult.empty,
        targetLanguage: 'ko',
      );
      expect(cues, isEmpty);
      verifyNever(() => translation.translateBatch(any(),
          target: any(named: 'target'), source: any(named: 'source')));
    });

    test('세그먼트 번역 후 큐 생성 + 원문 보존', () async {
      when(() => translation.translateBatch(
            any(),
            target: any(named: 'target'),
            source: any(named: 'source'),
          )).thenAnswer((_) async => <String>['안녕', '또 봐']);

      final recognition = RecognitionResult(
        segments: <TranscriptSegment>[
          word(0, 300, 'Hi.'),
          word(2000, 2300, 'Bye.'),
        ],
        detectedLanguageCode: 'en-US',
      );

      final builder = CueBuilder(translation);
      final cues = await builder.build(recognition, targetLanguage: 'ko');

      expect(cues.length, 2);
      expect(cues[0].text, '안녕');
      expect(cues[0].sourceText, 'Hi.');
      expect(cues[1].text, '또 봐');
      // 감지 언어를 source로 전달했는지 확인
      final captured = verify(() => translation.translateBatch(
            captureAny(),
            target: 'ko',
            source: captureAny(named: 'source'),
          )).captured;
      expect(captured.last, 'en-US');
    });
  });
}
