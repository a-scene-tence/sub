/// 앱 전역 상수: API 엔드포인트, 오디오 인코딩, 자막 세그먼트 규칙.
///
/// 인코딩 상수(샘플레이트/채널/포맷)는 `AudioExtractionService`의 ffmpeg 출력과
/// **반드시 일치**해야 한다. 불일치 시 STT가 에러 없이 빈/깨진 결과를 낸다.
class AppConfig {
  AppConfig._();

  // --- Google Cloud 엔드포인트 ---
  static const String sttRecognizeUrl =
      'https://speech.googleapis.com/v1/speech:recognize';
  static const String sttLongRunningUrl =
      'https://speech.googleapis.com/v1/speech:longrunningrecognize';
  static const String translateV2Url =
      'https://translation.googleapis.com/language/translate/v2';

  // --- 오디오 인코딩(ffmpeg 출력과 일치) ---
  static const String sttEncoding = 'LINEAR16';
  static const int sampleRateHertz = 16000;
  static const int audioChannels = 1;

  /// ffmpeg로 16kHz mono PCM WAV를 만드는 인자.
  static const List<String> ffmpegAudioArgs = <String>[
    '-vn', // 비디오 트랙 제거
    '-ac', '1', // mono
    '-ar', '16000', // 16kHz
    '-c:a', 'pcm_s16le', // LINEAR16
  ];

  // --- MVP 제약: 인라인 STT는 60초 한도 ---
  static const Duration maxInlineClipDuration = Duration(seconds: 60);

  // --- 자막 세그먼트 그룹화 규칙 ---
  /// 한 자막 큐의 최대 글자 수(가독성).
  static const int maxSegmentChars = 80;

  /// 한 자막 큐의 최대 지속 시간.
  static const Duration maxSegmentDuration = Duration(seconds: 6);

  /// 단어 사이 간격이 이 값을 넘으면 세그먼트를 분리한다(문장/호흡 경계).
  static const Duration segmentSplitGap = Duration(milliseconds: 700);

  // --- 언어 자동 감지 후보(BCP-47) ---
  /// STT `alternativeLanguageCodes`로 전달할 후보. 첫 항목이 기본 추정 언어.
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
}
