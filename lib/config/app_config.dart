/// 앱 전역 상수: API 엔드포인트, 오디오 인코딩, 자막 세그먼트 규칙.
///
/// 오디오는 플랫폼 네이티브 추출(Android MediaCodec / iOS AVAssetReader)로 16-bit mono
/// PCM WAV를 만든다. 샘플레이트는 소스 네이티브 레이트를 그대로 쓰며, STT 요청에는
/// `SpeechService`가 WAV 헤더에서 실제 레이트를 읽어 사용한다(아래 값은 헤더 파싱 실패 시 폴백).
class AppConfig {
  AppConfig._();

  // --- Google Cloud 엔드포인트 ---
  static const String sttRecognizeUrl =
      'https://speech.googleapis.com/v1/speech:recognize';
  static const String sttLongRunningUrl =
      'https://speech.googleapis.com/v1/speech:longrunningrecognize';
  static const String translateV2Url =
      'https://translation.googleapis.com/language/translate/v2';

  // --- 오디오 인코딩(네이티브 추출 출력과 일치) ---
  static const String sttEncoding = 'LINEAR16';

  /// WAV 헤더 파싱 실패 시 사용할 폴백 샘플레이트. 실제 값은 추출된 WAV 헤더에서 읽는다.
  static const int sampleRateHertz = 16000;
  static const int audioChannels = 1;

  // --- 긴 영상: 동기 STT(≤60초/10MB)를 우회하려 WAV를 청크로 분할 ---
  /// Google 동기 인식 한도(60초)보다 작게 잡은 청크 길이(안전 여유 + 10MB 한도 회피).
  /// 50초·48kHz mono 16-bit ≈ 4.8MB(base64 ≈ 6.4MB) < 10MB.
  static const Duration sttChunkDuration = Duration(seconds: 50);

  // --- 실시간(라이브) 자막: 재생 위치를 따라 짧은 구간만 인식·번역 ---
  /// 한 번에 추출·인식할 윈도우 길이(동기 STT 60초 한도 내, 한 번의 호출로 처리).
  static const Duration liveWindow = Duration(seconds: 15);

  /// 재생 위치보다 이만큼 앞서 미리 처리해 자막이 제때 보이도록 한다(지연 은닉).
  static const Duration liveLookahead = Duration(seconds: 5);

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
