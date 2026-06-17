import 'package:flutter/foundation.dart';

import '../config/app_config.dart';

/// 사용자 설정(번역 대상 언어, 원문 표시 여부, 소스 언어 힌트).
@immutable
class AppSettings {
  const AppSettings({
    this.targetLanguage = AppConfig.defaultTargetLanguage,
    this.showSource = false,
    this.languageHint,
  });

  /// 번역 대상 언어(ISO-639-1).
  final String targetLanguage;

  /// 자막에 원문도 함께 표시할지.
  final bool showSource;

  /// 소스 언어 힌트(BCP-47). null이면 자동 감지.
  final String? languageHint;

  AppSettings copyWith({
    String? targetLanguage,
    bool? showSource,
    String? languageHint,
    bool clearHint = false,
  }) {
    return AppSettings(
      targetLanguage: targetLanguage ?? this.targetLanguage,
      showSource: showSource ?? this.showSource,
      languageHint: clearHint ? null : (languageHint ?? this.languageHint),
    );
  }
}

class SettingsController extends ValueNotifier<AppSettings> {
  SettingsController() : super(const AppSettings());

  void setTargetLanguage(String iso) =>
      value = value.copyWith(targetLanguage: iso);

  void setShowSource(bool show) => value = value.copyWith(showSource: show);

  void setLanguageHint(String? hint) => value = hint == null
      ? value.copyWith(clearHint: true)
      : value.copyWith(languageHint: hint);
}
