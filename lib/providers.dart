import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/secrets.dart';
import 'services/audio_extraction_service.dart';
import 'services/cue_builder.dart';
import 'services/fallback_translation_service.dart';
import 'services/gemini_translation_service.dart';
import 'services/speech_service.dart';
import 'services/translation_service.dart';
import 'state/live_caption_controller.dart';
import 'state/settings_controller.dart';

/// API 키 공급자.
final secretsProvider = Provider<Secrets>((ref) => Secrets());

/// 사용자 설정.
final settingsProvider =
    ChangeNotifierProvider<SettingsController>((ref) => SettingsController());

/// 현재 저장된 API 키(없으면 null) — 설정 화면 표시/검증용.
final apiKeyProvider = FutureProvider<String?>((ref) {
  return ref.watch(secretsProvider).getApiKey();
});

/// 라이브 자막 컨트롤러 생성 인자.
typedef LiveArgs = ({
  String apiKey,
  String videoPath,
  String targetLanguage,
  String? languageHint,
});

/// 실시간(라이브) 자막 컨트롤러를 만든다.
///
/// 화면에서 키/영상 경로/설정을 읽은 뒤 `ref.read(liveCaptionControllerFactory)(args)`로
/// 생성한다. 윈도우(≤15초)는 한 번의 동기 호출로 처리되므로 청크 인식기는 쓰지 않는다.
final liveCaptionControllerFactory =
    Provider<LiveCaptionController Function(LiveArgs)>((ref) {
  return (LiveArgs a) => LiveCaptionController(
        extractor: AudioExtractionService(),
        speech: GoogleSpeechService(apiKey: a.apiKey),
        // 자연스러운 구어체 번역은 Gemini로, 실패 시 Google 번역 v2로 폴백.
        cueBuilder: CueBuilder(
          FallbackTranslationService(
            primary: GeminiTranslationService(apiKey: a.apiKey),
            secondary: GoogleTranslationService(apiKey: a.apiKey),
          ),
        ),
        videoPath: a.videoPath,
        targetLanguage: a.targetLanguage,
        languageHint: a.languageHint,
      );
});
