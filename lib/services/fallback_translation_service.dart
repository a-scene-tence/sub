import 'translation_service.dart';

/// [primary]로 먼저 번역하고, 실패하면 [secondary]로 폴백하는 번역 서비스.
///
/// Gemini(자연스러운 구어체)를 primary로, Google 번역 v2를 secondary로 두면
/// Gemini 호출이 실패(키 미설정·쿼터·모델 미가용 등)해도 실시간 자막이 끊기지 않는다.
/// 둘 다 [TranslationService]라 [CueBuilder]에는 투명하다.
class FallbackTranslationService implements TranslationService {
  FallbackTranslationService({
    required this.primary,
    required this.secondary,
  });

  final TranslationService primary;
  final TranslationService secondary;

  @override
  Future<List<String>> translateBatch(
    List<String> texts, {
    required String target,
    String? source,
  }) async {
    if (texts.isEmpty) return <String>[];
    try {
      return await primary.translateBatch(texts, target: target, source: source);
    } catch (_) {
      // primary 실패 시 조용히 secondary로 폴백(자막 연속성 우선).
      return secondary.translateBatch(texts, target: target, source: source);
    }
  }
}
