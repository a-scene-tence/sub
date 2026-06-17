import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/secrets.dart';
import 'services/audio_extraction_service.dart';
import 'services/cue_builder.dart';
import 'services/speech_service.dart';
import 'services/translation_service.dart';
import 'state/processing_controller.dart';
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

/// 주어진 API 키로 자막 파이프라인 컨트롤러를 만든다.
///
/// 화면에서 키를 읽은 뒤 `ref.read(processingControllerFactory)(key)`로 생성한다.
final processingControllerFactory =
    Provider<ProcessingController Function(String apiKey)>((ref) {
  return (String apiKey) {
    final speech = GoogleSpeechService(apiKey: apiKey);
    final translation = GoogleTranslationService(apiKey: apiKey);
    return ProcessingController(
      audioExtractor: AudioExtractionService(),
      speechService: speech,
      cueBuilder: CueBuilder(translation),
    );
  };
});
