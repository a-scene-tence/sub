import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:video_subtitle_translator/models/recognition_result.dart';
import 'package:video_subtitle_translator/models/subtitle_cue.dart';
import 'package:video_subtitle_translator/models/transcript_segment.dart';
import 'package:video_subtitle_translator/services/audio_extraction_service.dart';
import 'package:video_subtitle_translator/services/cue_builder.dart';
import 'package:video_subtitle_translator/services/speech_service.dart';
import 'package:video_subtitle_translator/services/translation_service.dart';
import 'package:video_subtitle_translator/state/processing_controller.dart';

class _MockAudio extends Mock implements AudioExtractor {}

class _MockRecognizer extends Mock implements AudioRecognizer {}

class _MockTranslation extends Mock implements TranslationService {}

class _FakeFile extends Fake implements File {}

void main() {
  late _MockAudio audio;
  late _MockRecognizer recognizer;
  late _MockTranslation translation;
  late File fakeFile;

  setUpAll(() {
    registerFallbackValue(_FakeFile());
  });

  setUp(() {
    audio = _MockAudio();
    recognizer = _MockRecognizer();
    translation = _MockTranslation();
    fakeFile = _FakeFile();
    when(() => audio.extractWav(any())).thenAnswer((_) async => fakeFile);
    when(() => audio.cleanup(any())).thenAnswer((_) async {});
  });

  ProcessingController makeController() => ProcessingController(
        audioExtractor: audio,
        recognizer: recognizer,
        cueBuilder: CueBuilder(translation),
      );

  test('성공 경로: idle -> ... -> ready 전이 + 임시파일 정리', () async {
    when(() => recognizer.recognizeFile(any(),
            languageHint: any(named: 'languageHint'),
            onProgress: any(named: 'onProgress')))
        .thenAnswer((_) async => RecognitionResult(
              segments: <TranscriptSegment>[
                TranscriptSegment(
                  start: Duration.zero,
                  end: const Duration(milliseconds: 500),
                  text: 'hi',
                  languageCode: 'en-US',
                ),
              ],
              detectedLanguageCode: 'en-US',
            ));
    when(() => translation.translateBatch(any(),
        target: any(named: 'target'),
        source: any(named: 'source'))).thenAnswer((_) async => <String>['안녕']);

    final controller = makeController();
    final seen = <ProcessingStatus>[];
    controller.addListener(() => seen.add(controller.value.status));

    await controller.process('video.mp4', targetLanguage: 'ko');

    expect(controller.value.status, ProcessingStatus.ready);
    expect(controller.value.cues, isNotEmpty);
    expect(controller.value.cues.first, isA<SubtitleCue>());
    expect(controller.value.detectedLanguage, 'en-US');
    expect(
        seen,
        containsAllInOrder(<ProcessingStatus>[
          ProcessingStatus.extracting,
          ProcessingStatus.recognizing,
          ProcessingStatus.translating,
          ProcessingStatus.ready,
        ]));
    verify(() => audio.cleanup(fakeFile)).called(1);
  });

  test('무음(빈 인식)은 error 상태', () async {
    when(() => recognizer.recognizeFile(any(),
            languageHint: any(named: 'languageHint'),
            onProgress: any(named: 'onProgress')))
        .thenAnswer((_) async => RecognitionResult.empty);

    final controller = makeController();
    await controller.process('video.mp4', targetLanguage: 'ko');

    expect(controller.value.status, ProcessingStatus.error);
    expect(controller.value.errorMessage, isNotNull);
    verify(() => audio.cleanup(fakeFile)).called(1);
  });

  test('STT 예외는 error 상태 + 정리', () async {
    when(() => recognizer.recognizeFile(any(),
            languageHint: any(named: 'languageHint'),
            onProgress: any(named: 'onProgress')))
        .thenThrow(SpeechException('boom'));

    final controller = makeController();
    await controller.process('video.mp4', targetLanguage: 'ko');

    expect(controller.value.status, ProcessingStatus.error);
    verify(() => audio.cleanup(fakeFile)).called(1);
  });
}
