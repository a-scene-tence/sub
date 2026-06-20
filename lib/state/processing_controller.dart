import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/subtitle_cue.dart';
import '../services/audio_extraction_service.dart';
import '../services/cue_builder.dart';
import '../services/diagnostics.dart';
import '../services/speech_service.dart';

/// 자막 생성 파이프라인의 진행 단계.
enum ProcessingStatus {
  idle,
  extracting, // 오디오 추출
  recognizing, // STT
  translating, // 번역 + 큐 생성
  ready,
  error,
}

@immutable
class ProcessingState {
  const ProcessingState({
    this.status = ProcessingStatus.idle,
    this.cues = const <SubtitleCue>[],
    this.detectedLanguage,
    this.errorMessage,
  });

  final ProcessingStatus status;
  final List<SubtitleCue> cues;
  final String? detectedLanguage;
  final String? errorMessage;

  bool get isBusy =>
      status == ProcessingStatus.extracting ||
      status == ProcessingStatus.recognizing ||
      status == ProcessingStatus.translating;

  ProcessingState copyWith({
    ProcessingStatus? status,
    List<SubtitleCue>? cues,
    String? detectedLanguage,
    String? errorMessage,
  }) {
    return ProcessingState(
      status: status ?? this.status,
      cues: cues ?? this.cues,
      detectedLanguage: detectedLanguage ?? this.detectedLanguage,
      errorMessage: errorMessage,
    );
  }
}

/// 영상 경로 -> 자막 큐 파이프라인을 구동하는 컨트롤러.
///
/// 단계: 오디오 추출 -> STT(언어감지) -> 번역/큐 생성. 각 서비스는 주입되어
/// 테스트에서 목으로 대체 가능하다.
class ProcessingController extends ValueNotifier<ProcessingState> {
  ProcessingController({
    required AudioExtractor audioExtractor,
    required SpeechService speechService,
    required CueBuilder cueBuilder,
  })  : _audio = audioExtractor,
        _speech = speechService,
        _cueBuilder = cueBuilder,
        super(const ProcessingState());

  final AudioExtractor _audio;
  final SpeechService _speech;
  final CueBuilder _cueBuilder;

  /// [videoPath]를 처리해 [targetLanguage] 자막 큐를 생성한다.
  Future<void> process(
    String videoPath, {
    required String targetLanguage,
    String? languageHint,
  }) async {
    File? extracted;
    try {
      value = const ProcessingState(status: ProcessingStatus.extracting);
      await Diagnostics.record('pipe: 오디오 추출 시작');
      extracted = await _audio.extractWav(videoPath);
      await Diagnostics.record('pipe: 오디오 추출 완료');
      final bytes = await extracted.readAsBytes();

      value = value.copyWith(status: ProcessingStatus.recognizing);
      await Diagnostics.record('pipe: STT 시작 (${bytes.length}B)');
      final recognition =
          await _speech.recognize(bytes, languageHint: languageHint);
      await Diagnostics.record('pipe: STT 완료 '
          '(${recognition.segments.length}seg, '
          '${recognition.detectedLanguageCode})');

      if (recognition.isEmpty) {
        await Diagnostics.record('pipe: 무음/미인식');
        value = const ProcessingState(
          status: ProcessingStatus.error,
          errorMessage: '음성을 인식하지 못했습니다(무음이거나 지원하지 않는 언어).',
        );
        return;
      }

      value = value.copyWith(
        status: ProcessingStatus.translating,
        detectedLanguage: recognition.detectedLanguageCode,
      );
      await Diagnostics.record('pipe: 번역/큐 생성 시작 (target=$targetLanguage)');
      final cues = await _cueBuilder.build(
        recognition,
        targetLanguage: targetLanguage,
      );

      value = ProcessingState(
        status: ProcessingStatus.ready,
        cues: cues,
        detectedLanguage: recognition.detectedLanguageCode,
      );
      await Diagnostics.record('pipe: 완료 (${cues.length} cues)');
      // 정상 완료 → 브레드크럼 삭제(다음 실행에서 오탐 방지).
      await Diagnostics.clear();
    } catch (e) {
      await Diagnostics.record('pipe: 예외: $e');
      value = ProcessingState(
        status: ProcessingStatus.error,
        errorMessage: e.toString(),
      );
    } finally {
      if (extracted != null) {
        await _audio.cleanup(extracted);
      }
    }
  }

  void reset() => value = const ProcessingState();
}
