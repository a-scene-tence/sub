import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// 사용자 설정(번역 대상 언어, 원문 표시 여부, 소스 언어 힌트, 자막 스타일).
@immutable
class AppSettings {
  const AppSettings({
    this.targetLanguage = AppConfig.defaultTargetLanguage,
    this.showSource = false,
    this.languageHint,
    this.subtitleFontSize = 20,
    this.subtitleTextColor = const Color(0xFFFFFFFF),
    this.subtitleBgColor = const Color(0xFF000000),
    this.subtitleBgOpacity = 0.6,
  });

  /// 번역 대상 언어(ISO-639-1).
  final String targetLanguage;

  /// 자막에 원문도 함께 표시할지.
  final bool showSource;

  /// 소스 언어 힌트(BCP-47). null이면 자동 감지.
  final String? languageHint;

  /// 자막 글자 크기(논리 픽셀).
  final double subtitleFontSize;

  /// 자막 글자색.
  final Color subtitleTextColor;

  /// 자막 배경색(투명도는 [subtitleBgOpacity]로 별도 적용).
  final Color subtitleBgColor;

  /// 자막 배경 투명도(0.0=투명 ~ 1.0=불투명).
  final double subtitleBgOpacity;

  AppSettings copyWith({
    String? targetLanguage,
    bool? showSource,
    String? languageHint,
    bool clearHint = false,
    double? subtitleFontSize,
    Color? subtitleTextColor,
    Color? subtitleBgColor,
    double? subtitleBgOpacity,
  }) {
    return AppSettings(
      targetLanguage: targetLanguage ?? this.targetLanguage,
      showSource: showSource ?? this.showSource,
      languageHint: clearHint ? null : (languageHint ?? this.languageHint),
      subtitleFontSize: subtitleFontSize ?? this.subtitleFontSize,
      subtitleTextColor: subtitleTextColor ?? this.subtitleTextColor,
      subtitleBgColor: subtitleBgColor ?? this.subtitleBgColor,
      subtitleBgOpacity: subtitleBgOpacity ?? this.subtitleBgOpacity,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'targetLanguage': targetLanguage,
        'showSource': showSource,
        'languageHint': languageHint,
        'subtitleFontSize': subtitleFontSize,
        'subtitleTextColor': _colorToArgb(subtitleTextColor),
        'subtitleBgColor': _colorToArgb(subtitleBgColor),
        'subtitleBgOpacity': subtitleBgOpacity,
      };

  /// 저장된 맵에서 복원한다. 누락/오류 필드는 기본값으로 폴백한다.
  factory AppSettings.fromMap(Map<String, dynamic> m) {
    const d = AppSettings();
    return AppSettings(
      targetLanguage: m['targetLanguage'] as String? ?? d.targetLanguage,
      showSource: m['showSource'] as bool? ?? d.showSource,
      languageHint: m['languageHint'] as String?,
      subtitleFontSize:
          (m['subtitleFontSize'] as num?)?.toDouble() ?? d.subtitleFontSize,
      subtitleTextColor: m['subtitleTextColor'] is int
          ? Color(m['subtitleTextColor'] as int)
          : d.subtitleTextColor,
      subtitleBgColor: m['subtitleBgColor'] is int
          ? Color(m['subtitleBgColor'] as int)
          : d.subtitleBgColor,
      subtitleBgOpacity:
          (m['subtitleBgOpacity'] as num?)?.toDouble() ?? d.subtitleBgOpacity,
    );
  }
}

/// [Color]를 0xAARRGGBB 정수로 변환한다(저장용). 신 컴포넌트 접근자(.a/.r/.g/.b, 0–1)를
/// 사용해 deprecated된 `Color.value`를 피한다.
int _colorToArgb(Color c) =>
    ((c.a * 255).round() << 24) |
    ((c.r * 255).round() << 16) |
    ((c.g * 255).round() << 8) |
    (c.b * 255).round();

/// 설정 상태 + SharedPreferences 영구 저장.
///
/// 생성 시 비동기로 [_load]하고(완료 전까지는 기본값), 각 setter에서 best-effort로
/// 저장한다. 저장/로드 실패는 기본값/현재값을 유지한다(설정은 앱 동작에 비치명적).
class SettingsController extends ValueNotifier<AppSettings> {
  SettingsController() : super(const AppSettings()) {
    loaded = _load();
  }

  static const String _prefsKey = 'app_settings';

  /// 초기 로드 완료 future(테스트/초기화 동기화용).
  late final Future<void> loaded;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      value = AppSettings.fromMap(map);
    } catch (_) {
      // best-effort: 기본값 유지.
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(value.toMap()));
    } catch (_) {
      // best-effort.
    }
  }

  void setTargetLanguage(String iso) {
    value = value.copyWith(targetLanguage: iso);
    _save();
  }

  void setShowSource(bool show) {
    value = value.copyWith(showSource: show);
    _save();
  }

  void setLanguageHint(String? hint) {
    value = hint == null
        ? value.copyWith(clearHint: true)
        : value.copyWith(languageHint: hint);
    _save();
  }

  void setSubtitleFontSize(double size) {
    value = value.copyWith(subtitleFontSize: size);
    _save();
  }

  void setSubtitleTextColor(Color color) {
    value = value.copyWith(subtitleTextColor: color);
    _save();
  }

  void setSubtitleBgColor(Color color) {
    value = value.copyWith(subtitleBgColor: color);
    _save();
  }

  void setSubtitleBgOpacity(double opacity) {
    value = value.copyWith(subtitleBgOpacity: opacity);
    _save();
  }
}
