/// 앱 전역 상수: Gemini 엔드포인트, 자막 세그먼트 규칙.
///
/// 오디오는 플랫폼 네이티브 추출(Android MediaCodec / iOS AVAssetReader)로 16-bit mono
/// PCM WAV를 만들고, 그대로 Gemini에 인라인으로 보내 전사+번역한다(Gemini가 WAV 헤더를 직접 해석).
class AppConfig {
  AppConfig._();

  /// Gemini(생성형 언어 API) 베이스 URL. 음성 인식·번역을 모두 처리.
  static const String geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  /// 사용할 Gemini 모델(빠르고 저렴, 오디오 멀티모달 지원).
  static const String geminiModel = 'gemini-2.5-flash';

  /// 지정 모델의 generateContent 엔드포인트를 만든다.
  static String geminiGenerateUrl(String model) =>
      '$geminiBaseUrl/$model:generateContent';

  // --- 실시간(라이브) 자막: 재생 위치를 따라 짧은 구간만 인식·번역 ---
  /// 한 번에 추출·인식할 윈도우 길이(짧을수록 타임스탬프 드리프트가 작다).
  static const Duration liveWindow = Duration(seconds: 15);

  /// 재생 위치보다 이만큼 앞서 미리 처리해 자막이 제때 보이도록 한다(지연 은닉).
  static const Duration liveLookahead = Duration(seconds: 5);

  // --- 자막 세그먼트 크기 가이드(캡션 프롬프트에 전달) ---
  /// 한 자막 큐의 최대 글자 수(가독성).
  static const int maxSegmentChars = 80;

  /// 한 자막 큐의 최대 지속 시간.
  static const Duration maxSegmentDuration = Duration(seconds: 6);

  // --- 소스 언어 힌트 후보(BCP-47, 설정 화면 드롭다운용) ---
  /// 사용자가 소스 언어를 수동 지정할 때 고를 수 있는 후보(기본은 자동 감지).
  static const List<String> languageCandidates = <String>[
    'en-US',
    'ko-KR',
    'ja-JP',
    'zh-CN',
    'es-ES',
    'fr-FR',
    'de-DE',
  ];

  /// 기본 번역 대상 언어(ISO-639-1).
  static const String defaultTargetLanguage = 'ko';

  // --- 웹페이지 URL에서 영상 파일 감지(VideoUrlResolver) ---
  /// 페이지를 가져올 때 보낼 브라우저 유사 User-Agent(일부 사이트의 기본 차단 회피).
  static const String webFetchUserAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36';

  /// 페이지 HTML 다운로드 타임아웃.
  static const Duration webFetchTimeout = Duration(seconds: 15);

  /// 다운로드할 HTML 최대 바이트(거대한 응답 보호).
  static const int webFetchMaxBytes = 5 * 1024 * 1024;

  /// 직접 미디어 링크로 인정할 확장자(소문자, 점 제외).
  static const Set<String> mediaFileExtensions = <String>{
    'mp4', 'm4v', 'mov', 'webm', 'mkv', 'ogv', 'avi', // progressive
    'm3u8', // HLS
    'mpd', // DASH
  };
}
