import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/secrets.dart';
import 'services/audio_extraction_service.dart';
import 'services/gemini_caption_service.dart';
import 'services/video_url_resolver.dart';
import 'state/live_caption_controller.dart';
import 'state/settings_controller.dart';

/// API 키 공급자.
final secretsProvider = Provider<Secrets>((ref) => Secrets());

/// 사용자 설정.
final settingsProvider =
    ChangeNotifierProvider<SettingsController>((ref) => SettingsController());

/// 웹페이지 URL에서 재생 가능한 영상 파일을 찾아내는 해석기.
final videoUrlResolverProvider =
    Provider<VideoUrlResolver>((ref) => VideoUrlResolver());

/// 현재 저장된 Gemini API 키(없으면 null) — 설정 화면 표시/검증용.
/// 이 앱은 음성 인식·번역을 모두 Gemini로 처리하므로 이 키 하나만 필요하다.
final geminiApiKeyProvider = FutureProvider<String?>((ref) {
  return ref.watch(secretsProvider).getGeminiApiKey();
});

/// 라이브 자막 컨트롤러 생성 인자.
typedef LiveArgs = ({
  String apiKey, // Gemini(AI Studio) 키.
  String videoPath,
  String targetLanguage,
  String? languageHint,
});

/// 실시간(라이브) 자막 컨트롤러를 만든다.
///
/// 화면에서 키/영상 경로/설정을 읽은 뒤 `ref.read(liveCaptionControllerFactory)(args)`로
/// 생성한다. 오디오 윈도우(≤15초)를 Gemini 단일 호출로 전사+번역한다.
final liveCaptionControllerFactory =
    Provider<LiveCaptionController Function(LiveArgs)>((ref) {
  return (LiveArgs a) {
    return LiveCaptionController(
      extractor: AudioExtractionService(),
      caption: GeminiCaptionService(apiKey: a.apiKey),
      videoPath: a.videoPath,
      targetLanguage: a.targetLanguage,
      languageHint: a.languageHint,
    );
  };
});
