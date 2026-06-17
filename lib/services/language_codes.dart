/// BCP-47 STT 언어 코드(`en-US`)를 Translation v2의 ISO-639-1 코드(`en`)로 변환.
String toIsoLanguage(String bcp47) {
  final trimmed = bcp47.trim();
  if (trimmed.isEmpty) return '';
  // `zh-CN`/`zh-Hans` 등은 앞부분(`zh`)만 사용. 대소문자 정규화.
  final base = trimmed.split(RegExp('[-_]')).first.toLowerCase();
  return base;
}

/// 사람이 읽는 언어명(설정 UI용). 미정의 코드는 코드 자체를 반환.
const Map<String, String> kLanguageNames = <String, String>{
  'ko': '한국어',
  'en': 'English',
  'ja': '日本語',
  'zh': '中文',
  'es': 'Español',
  'fr': 'Français',
  'de': 'Deutsch',
  'it': 'Italiano',
  'pt': 'Português',
  'ru': 'Русский',
  'vi': 'Tiếng Việt',
  'th': 'ไทย',
};

String languageDisplayName(String isoCode) =>
    kLanguageNames[toIsoLanguage(isoCode)] ?? isoCode;
