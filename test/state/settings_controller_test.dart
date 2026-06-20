import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_subtitle_translator/state/settings_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppSettings', () {
    test('copyWith로 스타일 필드 갱신', () {
      const s = AppSettings();
      final s2 = s.copyWith(
        subtitleFontSize: 28,
        subtitleTextColor: const Color(0xFFFFEB3B),
        subtitleBgOpacity: 0.3,
      );
      expect(s2.subtitleFontSize, 28);
      expect(s2.subtitleTextColor, const Color(0xFFFFEB3B));
      expect(s2.subtitleBgOpacity, 0.3);
      // 미지정 필드는 보존.
      expect(s2.subtitleBgColor, s.subtitleBgColor);
      expect(s2.targetLanguage, s.targetLanguage);
    });

    test('toMap/fromMap 라운드트립(색상 포함)', () {
      const s = AppSettings(
        targetLanguage: 'ja',
        showSource: true,
        languageHint: 'en-US',
        subtitleFontSize: 26,
        subtitleTextColor: Color(0xFF40C4FF),
        subtitleBgColor: Color(0xFF1A237E),
        subtitleBgOpacity: 0.45,
      );
      final restored = AppSettings.fromMap(s.toMap());
      expect(restored.targetLanguage, 'ja');
      expect(restored.showSource, true);
      expect(restored.languageHint, 'en-US');
      expect(restored.subtitleFontSize, 26);
      expect(restored.subtitleTextColor, const Color(0xFF40C4FF));
      expect(restored.subtitleBgColor, const Color(0xFF1A237E));
      expect(restored.subtitleBgOpacity, 0.45);
    });

    test('fromMap: 누락 필드는 기본값 폴백', () {
      final s = AppSettings.fromMap(<String, dynamic>{'targetLanguage': 'fr'});
      expect(s.targetLanguage, 'fr');
      expect(s.subtitleFontSize, const AppSettings().subtitleFontSize);
      expect(s.subtitleTextColor, const AppSettings().subtitleTextColor);
    });
  });

  group('SettingsController 영구 저장', () {
    test('저장된 값을 생성 시 로드', () async {
      const saved = AppSettings(targetLanguage: 'de', subtitleFontSize: 30);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'app_settings': jsonEncode(saved.toMap()),
      });

      final c = SettingsController();
      await c.loaded;

      expect(c.value.targetLanguage, 'de');
      expect(c.value.subtitleFontSize, 30);
    });

    test('setter가 SharedPreferences에 저장', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final c = SettingsController();
      await c.loaded;

      c.setSubtitleFontSize(24);
      c.setSubtitleTextColor(const Color(0xFFFF9800));
      // 비동기 저장이 끝나도록 한 틱 양보.
      await Future<void>.delayed(Duration.zero);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('app_settings');
      expect(raw, isNotNull);
      final restored =
          AppSettings.fromMap(jsonDecode(raw!) as Map<String, dynamic>);
      expect(restored.subtitleFontSize, 24);
      expect(restored.subtitleTextColor, const Color(0xFFFF9800));
    });
  });
}
