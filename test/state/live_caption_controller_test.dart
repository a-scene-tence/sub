import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:video_player/video_player.dart';
import 'package:video_subtitle_translator/engine/subtitle_sync_engine.dart';
import 'package:video_subtitle_translator/models/recognition_result.dart';
import 'package:video_subtitle_translator/models/transcript_segment.dart';
import 'package:video_subtitle_translator/services/audio_extraction_service.dart';
import 'package:video_subtitle_translator/services/cue_builder.dart';
import 'package:video_subtitle_translator/services/speech_service.dart';
import 'package:video_subtitle_translator/services/translation_service.dart';
import 'package:video_subtitle_translator/state/live_caption_controller.dart';
import 'package:video_subtitle_translator/state/player_controller.dart';

class _MockVideo extends Mock implements VideoPlayerController {}

/// 요청된 구간을 기록하고 임시 WAV 파일을 돌려주는 가짜 추출기.
class _RecordingExtractor implements AudioExtractor {
  _RecordingExtractor(this._dir);
  final Directory _dir;
  final List<({Duration? start, Duration? end})> requests =
      <({Duration? start, Duration? end})>[];
  int cleanups = 0;

  @override
  Future<File> extractWav(String videoPath,
      {Duration? start, Duration? end}) async {
    requests.add((start: start, end: end));
    final f = File('${_dir.path}/w${requests.length}.wav');
    await f.writeAsBytes(List<int>.filled(64, 0));
    return f;
  }

  @override
  Future<void> cleanup(File file) async {
    cleanups++;
    if (file.existsSync()) file.deleteSync();
  }
}

/// 호출마다 0.5~1.0초 세그먼트 하나를 돌려주는 가짜 STT(에러/무음 주입 가능).
class _FakeSpeech implements SpeechService {
  _FakeSpeech({this.result, this.error});
  RecognitionResult? result;
  Object? error;
  int calls = 0;

  @override
  Future<RecognitionResult> recognize(List<int> audioBytes,
      {String? languageHint}) async {
    calls++;
    if (error != null) throw error!;
    return result ??
        RecognitionResult(
          segments: <TranscriptSegment>[
            TranscriptSegment(
              start: const Duration(milliseconds: 500),
              end: const Duration(seconds: 1),
              text: 'seg',
              languageCode: 'en-US',
            ),
          ],
          detectedLanguageCode: 'en-US',
        );
  }
}

/// 입력 텍스트를 그대로 돌려주는 가짜 번역기(네트워크 없이 큐 생성 검증용).
class _EchoTranslation implements TranslationService {
  @override
  Future<List<String>> translateBatch(List<String> texts,
          {required String target, String? source}) async =>
      List<String>.from(texts);
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('live_test');
  });
  tearDown(() async {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// duration 1시간, 지정 위치/재생상태의 비디오 값.
  VideoPlayerValue videoValue(Duration pos, {bool playing = true}) =>
      VideoPlayerValue(
        duration: const Duration(hours: 1),
        position: pos,
        isInitialized: true,
        isPlaying: playing,
      );

  LiveCaptionController makeController(
    _RecordingExtractor extractor,
    _FakeSpeech speech, {
    Duration window = const Duration(seconds: 10),
    Duration lookahead = const Duration(seconds: 5),
  }) =>
      LiveCaptionController(
        extractor: extractor,
        speech: speech,
        cueBuilder: CueBuilder(_EchoTranslation()),
        videoPath: '/video.mp4',
        targetLanguage: 'ko',
        window: window,
        lookahead: lookahead,
      );

  test('연속 윈도우: frontier 전진 + 큐 시각 오프셋 보정', () async {
    final extractor = _RecordingExtractor(tmp);
    final speech = _FakeSpeech();
    final video = _MockVideo();
    final player = PlayerController();
    final controller = makeController(extractor, speech)..enabled = true;
    controller.bindForTest(video, player);
    addTearDown(() {
      controller.dispose();
      player.dispose();
    });

    when(() => video.value).thenReturn(videoValue(Duration.zero));
    await controller.stepOnce(); // [0,10)
    expect(controller.processedEnd, const Duration(seconds: 10));

    // 재생이 진행됐다고 가정하고 두 번째 윈도우 처리.
    when(() => video.value).thenReturn(videoValue(const Duration(seconds: 8)));
    await controller.stepOnce(); // [10,20)

    expect(extractor.requests, <({Duration? start, Duration? end})>[
      (start: Duration.zero, end: const Duration(seconds: 10)),
      (start: const Duration(seconds: 10), end: const Duration(seconds: 20)),
    ]);
    // 첫 윈도우 큐 0.5~1.0s, 둘째 윈도우는 +10s 보정되어 10.5~11.0s.
    expect(controller.cues.length, 2);
    expect(controller.cues[0].start, const Duration(milliseconds: 500));
    expect(controller.cues[1].start, const Duration(milliseconds: 10500));
  });

  test('앞으로 탐색: 건너뛴 구간은 추출하지 않고 재생 위치부터', () async {
    final extractor = _RecordingExtractor(tmp);
    final controller = makeController(extractor, _FakeSpeech())..enabled = true;
    final video = _MockVideo();
    final player = PlayerController();
    controller.bindForTest(video, player);
    addTearDown(() {
      controller.dispose();
      player.dispose();
    });

    when(() => video.value).thenReturn(videoValue(Duration.zero));
    await controller.stepOnce(); // [0,10), frontier=10

    // 500초로 점프(미처리 구간) → frontier 점프, [500,510)만 추출.
    when(() => video.value)
        .thenReturn(videoValue(const Duration(seconds: 500)));
    await controller.stepOnce();

    expect(extractor.requests.last.start, const Duration(seconds: 500));
    expect(extractor.requests.length, 2);
  });

  test('뒤로 탐색(이미 처리된 구간): 추가 추출 없음, 큐 유지', () async {
    final extractor = _RecordingExtractor(tmp);
    final controller = makeController(extractor, _FakeSpeech())..enabled = true;
    final video = _MockVideo();
    final player = PlayerController();
    controller.bindForTest(video, player);
    addTearDown(() {
      controller.dispose();
      player.dispose();
    });

    when(() => video.value).thenReturn(videoValue(Duration.zero));
    await controller.stepOnce(); // [0,10), frontier=10
    final cuesBefore = controller.cues.length;

    // 3초로 되감기: frontier(10) > pos(3)+lookahead(5)=8 → 처리 안 함.
    when(() => video.value).thenReturn(videoValue(const Duration(seconds: 3)));
    await controller.stepOnce();

    expect(extractor.requests.length, 1);
    expect(controller.cues.length, cuesBefore);
  });

  test('토글 OFF: 아무것도 처리하지 않음', () async {
    final extractor = _RecordingExtractor(tmp);
    final controller = makeController(extractor, _FakeSpeech())
      ..enabled = false;
    final video = _MockVideo();
    final player = PlayerController();
    controller.bindForTest(video, player);
    addTearDown(() {
      controller.dispose();
      player.dispose();
    });

    when(() => video.value).thenReturn(videoValue(Duration.zero));
    await controller.stepOnce();
    expect(extractor.requests, isEmpty);
  });

  test('일시정지: 처리하지 않음', () async {
    final extractor = _RecordingExtractor(tmp);
    final controller = makeController(extractor, _FakeSpeech())..enabled = true;
    final video = _MockVideo();
    final player = PlayerController();
    controller.bindForTest(video, player);
    addTearDown(() {
      controller.dispose();
      player.dispose();
    });

    when(() => video.value)
        .thenReturn(videoValue(Duration.zero, playing: false));
    await controller.stepOnce();
    expect(extractor.requests, isEmpty);
  });

  test('무음(빈 인식): frontier만 전진, 큐 없음', () async {
    final extractor = _RecordingExtractor(tmp);
    final speech = _FakeSpeech(result: RecognitionResult.empty);
    final controller = makeController(extractor, speech)..enabled = true;
    final video = _MockVideo();
    final player = PlayerController();
    controller.bindForTest(video, player);
    addTearDown(() {
      controller.dispose();
      player.dispose();
    });

    when(() => video.value).thenReturn(videoValue(Duration.zero));
    await controller.stepOnce();

    expect(controller.processedEnd, const Duration(seconds: 10));
    expect(controller.cues, isEmpty);
    expect(controller.value.status, LiveStatus.idle);
  });

  test('에러: status=error, frontier 유지, 임시파일 정리', () async {
    final extractor = _RecordingExtractor(tmp);
    final speech = _FakeSpeech(error: SpeechException('boom'));
    final controller = makeController(extractor, speech)..enabled = true;
    final video = _MockVideo();
    final player = PlayerController();
    controller.bindForTest(video, player);
    addTearDown(() {
      controller.dispose();
      player.dispose();
    });

    when(() => video.value).thenReturn(videoValue(Duration.zero));
    await controller.stepOnce();

    expect(controller.value.status, LiveStatus.error);
    expect(controller.processedEnd, Duration.zero); // 전진하지 않음 → 재시도.
    expect(extractor.cleanups, 1); // 임시파일 정리됨.
  });

  test('병합 결과는 정렬·비중첩 불변식을 만족(SubtitleSyncEngine 구성)', () async {
    final extractor = _RecordingExtractor(tmp);
    final controller = makeController(extractor, _FakeSpeech())..enabled = true;
    final video = _MockVideo();
    final player = PlayerController();
    controller.bindForTest(video, player);
    addTearDown(() {
      controller.dispose();
      player.dispose();
    });

    when(() => video.value).thenReturn(videoValue(Duration.zero));
    await controller.stepOnce();
    when(() => video.value).thenReturn(videoValue(const Duration(seconds: 8)));
    await controller.stepOnce();

    // 정렬·비중첩이 아니면 생성자 assert가 던진다.
    expect(() => SubtitleSyncEngine(controller.cues), returnsNormally);
  });
}
