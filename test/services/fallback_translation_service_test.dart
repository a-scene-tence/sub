import 'package:flutter_test/flutter_test.dart';
import 'package:video_subtitle_translator/services/fallback_translation_service.dart';
import 'package:video_subtitle_translator/services/translation_service.dart';

/// 호출 기록·결과/예외를 제어할 수 있는 가짜 번역 서비스.
class _FakeTranslation implements TranslationService {
  _FakeTranslation({this.result, this.error});

  final List<String>? result;
  final Object? error;
  int calls = 0;

  @override
  Future<List<String>> translateBatch(
    List<String> texts, {
    required String target,
    String? source,
  }) async {
    calls++;
    if (error != null) throw error!;
    return result ?? texts;
  }
}

void main() {
  group('FallbackTranslationService', () {
    test('빈 입력은 둘 다 호출 없이 빈 결과', () async {
      final primary = _FakeTranslation(result: <String>['x']);
      final secondary = _FakeTranslation(result: <String>['y']);
      final svc =
          FallbackTranslationService(primary: primary, secondary: secondary);
      expect(await svc.translateBatch(<String>[], target: 'ko'), isEmpty);
      expect(primary.calls, 0);
      expect(secondary.calls, 0);
    });

    test('primary 성공 시 secondary 미호출', () async {
      final primary = _FakeTranslation(result: <String>['안녕']);
      final secondary = _FakeTranslation(result: <String>['폴백']);
      final svc =
          FallbackTranslationService(primary: primary, secondary: secondary);
      final out = await svc.translateBatch(<String>['hi'], target: 'ko');
      expect(out, <String>['안녕']);
      expect(primary.calls, 1);
      expect(secondary.calls, 0);
    });

    test('primary 예외 시 secondary 결과로 폴백', () async {
      final primary = _FakeTranslation(error: TranslationException('실패'));
      final secondary = _FakeTranslation(result: <String>['폴백']);
      final svc =
          FallbackTranslationService(primary: primary, secondary: secondary);
      final out = await svc
          .translateBatch(<String>['hi'], target: 'ko', source: 'en-US');
      expect(out, <String>['폴백']);
      expect(primary.calls, 1);
      expect(secondary.calls, 1);
    });
  });
}
