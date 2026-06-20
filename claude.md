# 개발 규칙·제약사항 (claude.md)

> 작업하면서 지속 업데이트. **오류·버그 발생 시 [9. 버그/오류 로그](#9-버그오류-로그)에 즉시
> 기록**하여 동일 문제 재발을 방지한다.

## 1. 아키텍처 규칙

- **순수 로직 분리**: 자막 동기화·세그먼트 그룹화·응답 파싱 등 핵심 로직은 Flutter/디바이스에
  의존하지 않는 순수 Dart로 작성한다(`lib/engine`, `lib/models`, 파싱 함수). → 디바이스 없이
  `flutter test`로 검증 가능.
- **디바이스 의존 코드 격리**: ffmpeg, `video_player`, `file_picker`, secure storage 등은
  서비스 인터페이스(`AudioExtractor`, `SpeechService`, `TranslationService`) 뒤에 두고
  테스트에서 목으로 대체한다.
- **상수 집중**: 엔드포인트·인코딩·세그먼트 규칙은 `lib/config/app_config.dart` 한 곳에서 관리.
- **확장성**: 실시간 STT/장편 처리는 기존 인터페이스를 구현해 추가(스텁만 둠).

## 2. 코딩 규칙

- `analysis_options.yaml`(= `flutter_lints` 기반) 준수. 커밋 전 `flutter analyze` **무경고**.
- 커밋 전 `dart format .` 적용.
- `print` 금지(`avoid_print`). 진단은 향후 로거로.
- 불변 모델(`@immutable`) + 값 동등성(`==`/`hashCode`) 유지.
- 외부 입력(API 응답)은 항상 방어적으로 파싱(타입 체크·null 처리·빈 결과 허용).

## 3. 보안 제약 (필수)

- **API 키·비밀을 절대 커밋하지 않는다.** `.env`, 서비스계정 JSON, 키스토어는 `.gitignore`에 포함.
- 키는 **로그·예외 메시지·UI에 노출하지 않는다**(예외 메시지 작성 시 키 문자열 미포함 확인).
- 런타임 키는 `flutter_secure_storage`에 저장. 빌드 시 키는 `.env`(로컬, 커밋 금지).
- keystore 불가/무한대기 기기(9.11, 9.12)에서는 **SharedPreferences / 앱 전용(샌드박스)
  평문 파일**로 폴백 저장한다. 둘 다 앱 샌드박스라 외부 앱 접근은 불가하나 루팅/디바이스
  백업 시 노출 위험이 있어 **MVP 데모 한정**이며, Cloud Console 키 제한(API 종류 +
  앱 ID/SHA-1)을 전제로 한다.
- 모바일 바이너리의 키는 추출 가능 → Cloud Console에서 **API 종류 + 앱 ID/SHA-1로 제한**.
- 프로덕션은 백엔드 프록시로 키를 숨기는 것이 원칙(MVP는 데모 한정, 위험 문서화).

## 4. Google Cloud API 제약

- **인라인 STT는 오디오 60초 한도.** 초과 시 GCS `gs://` URI + `longRunningRecognize` 필요(Phase 2).
- STT `config`의 `encoding`/`sampleRateHertz`/`audioChannelCount`는 **ffmpeg 출력과 정확히 일치**해야
  한다. 불일치 시 에러 없이 빈/깨진 전사가 나온다. → `AppConfig.ffmpegAudioArgs`와
  `AppConfig.sttEncoding/sampleRateHertz/audioChannels`를 함께 변경.
- STT 단어 오프셋은 `"1.300s"` 형태 문자열 → `parseSttDuration`으로 견고 파싱(음수/NaN/null→0).
- 번역 v2는 BCP-47(`en-US`)이 아닌 ISO-639-1(`en`)을 받음 → `toIsoLanguage`로 변환.
  `source==target`이면 호출 생략. 응답의 HTML 엔티티(`&#39;`)는 디코드.
- 쿼터/비용: 세그먼트를 **배치(`q[]`)로 묶어** 호출 수·비용 절감.

## 5. 라이선스 주의

- `ffmpeg_kit_flutter_new`는 폐기된 `ffmpeg_kit_flutter`의 커뮤니티 포크이며 full-GPL 빌드.
  배포 시 **GPL 함의**를 검토한다. 버전은 핀 고정(`pubspec.yaml`).

## 6. 권한

- **마이크 권한 불필요**(파일 기반). 요청하지 말 것.
- 파일 접근·네트워크만 필요. Android scoped storage, iOS 문서 picker 엔트리 확인.
  http URL 사용 시 Android cleartext 설정 필요할 수 있음.

## 7. 테스트 규칙

- 새 순수 로직에는 단위 테스트 동반. HTTP 서비스는 `MockClient`/`mocktail`로 목.
- 비-ASCII 응답을 테스트할 때 `http.Response`에 `content-type: …; charset=utf-8` 지정
  (미지정 시 latin1로 인코딩되어 한글 등에서 실패 — 9.5 참고).
- `mocktail`에서 커스텀 타입을 `any()`로 매칭하려면 `registerFallbackValue` 등록.

## 8. 빌드/검증 절차

```bash
flutter pub get
dart format .
flutter analyze      # 무경고여야 함
flutter test         # 전부 통과여야 함
```

## 9. 버그/오류 로그

> 형식: 증상 → 원인 → 해결 → 재발 방지. 새 항목은 위에 추가.

### 9.17 원인 확정(16KB 페이지) → FFmpegKit 제거, 네이티브 오디오 추출로 교체
- **증상**: 9.16 캡처 배너가 실기기(삼성 SM-S938N/Galaxy S25, **API 36**)에서 표시 →
  `UnsatisfiedLinkError: Bad JNI version returned from JNI_OnLoad in`
  `".../lib/arm64-v8a/libffmpegkit_abidetect.so": 0`.
- **원인**: FFmpegKit ABI 감지용 `libffmpegkit_abidetect.so`가 로드 시 잘못된 JNI 버전(0) 반환 →
  런타임 거부. **Android 15/16 16KB 페이지 정렬 비호환**(arthenica/ffmpeg-kit#1000)의 전형적
  증상. `ffmpeg_kit_flutter_new` 4.2.1은 2.0.0부터 "16KB 호환 AAR"을 표방하나 이 기기에서 실패.
  FFmpegKit은 폐기(retired)되어 또 다른 포크 교체도 같은 위험.
- **해결**: FFmpeg 의존성 **완전 제거**. 앱이 FFmpeg를 쓰던 유일 용도(영상→16-bit mono PCM 추출)를
  플랫폼 네이티브로 교체 — Android `MediaExtractor`+`MediaCodec`, iOS `AVAssetReader`(둘 다 신규
  `AudioExtractor`), `MethodChannel('.../audio')`로 노출. 샘플레이트는 소스 네이티브 레이트 유지
  (리샘플 없음), WAV 헤더에 기록 → `SpeechService.recognize`가 헤더(바이트 24–27)에서 실제 레이트를
  읽어 STT 요청에 사용(`wavSampleRate`/`wavChannels`, 실패 시 `AppConfig` 폴백). `AudioExtractor`
  추상 인터페이스·`processing_controller`·`recognize` 시그니처는 무변경 → 변경 표면 최소.
  번들 `.so` 제거로 16KB/JNI/dlopen 실패 클래스 영구 제거 + APK 수십 MB 감소.
- **재발 방지**: 단일·협소 용도로 거대 네이티브 바이너리(특히 폐기된 프로젝트)를 끌어오지 말 것.
  OS 기본 미디어 API(MediaCodec/AVAssetReader)로 충분하면 그쪽이 16KB·ABI·유지보수에서 안전하다.

### 9.16 FFmpegKitConfig 정적 초기화 실패로 좁힘 → 원인 체인 캡처
- **증상**: 9.15 진단 배너가 `native: ffmpeg 재등록 실패: NoClassDefFoundError:
  com.antonkarpenko.ffmpegkit.FFmpegKitConfig` 표시. 즉 ffmpeg 플러그인은 로드되나 코어 클래스
  `FFmpegKitConfig` 참조에서 죽음.
- **원인(정적 분석으로 범위 축소, 빌드 없이)**: 게시된 APK(274MB)를 받아 검사 →
  (1) 4개 ABI 모두 네이티브 `.so` 존재(`libffmpegkit.so` 등), (2) 앱에 R8/minify 꺼짐(android/에
  `minifyEnabled` 없음) → 클래스 스트립 아님, (3) dex 원시 바이트에 `FFmpegKitConfig` 디스크립터
  존재. → 클래스·.so 모두 APK에 있음에도 죽으므로 **`FFmpegKitConfig.<clinit>`(정적 초기화)가
  기기에서 실패**로 확정. 최초 로드가 `ExceptionInInitializerError`를 던졌고(자동 등록 시점,
  GeneratedPluginRegistrant try/catch로 삼켜짐), 재attach가 이미 실패한 클래스를 만나
  `NoClassDefFoundError`를 본 것. 실제 사유(Caused by)는 기기에서만 드러남(APK 분석 불가).
- **진단 조치**: `MainActivity.onCreate`에서 `super.onCreate()` 호출 **전에**
  `Class.forName("...FFmpegKitConfig")`(initialize=true)로 최초 `<clinit>`를 우리가 먼저 트리거하고,
  실패 시 예외의 cause 체인을 한 줄로 진단 배너 파일에 기록. 자동 등록이 최초 로드를 가로채기
  전에 원본 예외를 잡기 위함. 9.15의 remove+add 블록은 정보가 없어 제거. (임시 코드)
- **수정 분기(캡처될 사유별)**: `UnsatisfiedLinkError ...16 KB/aligned` → 기기 16KB 페이지, .so
  미정렬 → 패키지 상향/대체; `dlopen ... not found`/압축 → `useLegacyPackaging true` 또는
  `extractNativeLibs=true`; `text relocations` → 구형 .so → 대체; `NoClassDefFoundError: <다른클래스>`
  → 코어 AAR 일부 미패키징 → 의존성 명시/대체.
- **재발 방지**: `NoClassDefFoundError`(≠ClassNotFoundException)는 대개 정적 초기화 실패다. 원본
  cause는 최초 로드에서만 나오므로, 의심 클래스를 자동 등록 전에 선로딩해 cause 체인을 잡는다.

### 9.15 ffmpeg 이벤트 채널 MissingPluginException(등록 실패 원인 진단)
- **증상**: 진단 배너(9.14)가 실기기에서 포착 — `FlutterError: MissingPluginException(No
  implementation found for method listen on channel flutter.arthenica.com/ffmpeg_kit_event)`.
  자막 파이프라인 첫 단계(오디오 추출)에서 FFmpegKit 이벤트 채널에 네이티브 핸들러가 없어 죽음.
  (`ffmpeg_kit_flutter_new` 4.2.1은 `FFmpegKitConfig` 지연 초기화에서 이벤트 채널 `listen`을
  가장 먼저 호출 → "플러그인 네이티브 측이 채널을 서빙 못함"의 신호.)
- **원인(미확정 → 진단 중)**: 플러그인 클래스 `com.antonkarpenko.ffmpegkit.FFmpegKitFlutterPlugin`는
  `GeneratedPluginRegistrant` 등록 목록엔 있고 다른 6개 플러그인(path_provider 등)은 정상. 그러나
  `GeneratedPluginRegistrant`의 각 등록은 `onAttachedToEngine` 예외를 **try/catch로 로그만 남기고
  삼킴** → ffmpeg attach가 던지면 채널이 조용히 미등록될 수 있음. 기기 logcat 없이는 사유 미확정.
  툴체인 스큐 존재(4.2.1은 changelog상 Flutter 3.29/Kotlin 2.2.0 겨냥, CI는 3.27.1/1.8.22).
- **진단 조치**: 추측 전 사유 캡처. `MainActivity.configureFlutterEngine`에서 이미 등록된 ffmpeg
  플러그인을 `flutterEngine.plugins.remove(cls)` 후 `add(new ...)`로 **재attach**하고, 그때의
  실제 예외(또는 성공)를 진단 배너가 읽는 동일 파일(`filesDir/last_breadcrumb.txt`)에 기록.
  경로 일치 근거: `path_provider_android`의 `getApplicationSupportPath()` =
  `io.flutter.util.PathUtils.getFilesDir(ctx)` = `context.getFilesDir()` == 네이티브 `filesDir`.
  배너 결과로 분기: "재등록 실패: <예외>" → 등록이 원인(예외가 사유 제공); "재등록 성공(등록 정상)"
  → 등록은 정상, 원인은 채널명/버전 스큐 → Flutter 3.29 상향 또는 의존성 교체로 피벗. (임시 코드)
- **재발 방지**: 네이티브 플러그인 등록 실패는 `GeneratedPluginRegistrant`가 삼키므로, 의심 시
  해당 플러그인만 remove+add로 재attach해 예외를 가시화한다(전체 자동 등록 비활성화는 9.13 회귀 위험).

### 9.14 자막 파이프라인이 네이티브 크래시로 조용히 종료, 멈춘 단계 불명
- **증상**: 영상 처리 중 앱이 죽거나 멈추는데, 어느 단계(오디오 추출/STT/번역)에서 멈췄는지
  알 수 없음. FFmpegKit 추출·대용량 오디오 STT 구간은 Dart `catch`로 잡히지 않는 네이티브
  크래시(SIGSEGV/OOM)가 가능해 `ProcessingIndicator`의 `e.toString()`도 못 띄움.
- **원인**: `Diagnostics` 유틸은 있었으나 파이프라인 계측이 없었고(`processing_controller.dart`가
  `diagnostics.dart`를 import만 하고 미사용), `Diagnostics.read()`/`clear()`도 어디서도 호출되지
  않아 브레드크럼이 사용자에게 표면화되지 않았음.
- **해결**: `process()` 각 단계 직전/직후 `Diagnostics.record('pipe: ...')` 추가 + 정상 완료 시
  `Diagnostics.clear()`. `HomeScreen.initState`의 post-frame에서 `Diagnostics.read()` →
  값이 있으면 dismissible `MaterialBanner('이전 실행 기록: ...')`로 표시(`닫기`가 `clear()`).
- **재발 방지**: 위험한 네이티브 호출 구간은 직전 브레드크럼을 남겨 "어디까지 갔나"를 디스크에
  보존하고, 정상 경로에서만 clear해 다음 실행 배너가 "비정상 종료 시"에만 뜨게 한다.

### 9.13 릴리스 APK에서 모든 네이티브 플러그인 미등록(MissingPluginException)
- **증상**: 빌드 #5 진단 노출 결과 키 저장 시 secure_storage(MissingPluginException),
  shared_preferences(PlatformException channel-error), path_provider(디렉터리 조회 실패)가
  **동시에** 실패. 서로 다른 저자의 독립 플러그인 3종이 모두 "채널에 핸들러 없음".
- **원인**: 개별 플러그인 버그가 아니라 **릴리스 APK에서 네이티브 플러그인이 FlutterEngine에
  attach되지 않음** = `GeneratedPluginRegistrant.registerWith(engine)`가 UI 엔진에 대해
  호출되지 않음. Android 구성은 표준·정상(settings.gradle flutter-plugin-loader, app build.gradle
  flutter-gradle-plugin, MainActivity=FlutterActivity, flutterEmbedding=2, 생성 registrant에
  7개 플러그인 포함, 네이티브 lib 포함, CI 무에러)인데도 리플렉션 기반 자동 등록이 누락됨.
- **해결**: `MainActivity.configureFlutterEngine()`를 오버라이드해
  `GeneratedPluginRegistrant.registerWith(flutterEngine)`를 **명시적으로 호출**. 자동 등록이
  동작한 경우에도 중복 add는 엔진 레지스트리가 무시하므로 멱등·무해.
- **재발 방지**: 여러 네이티브 플러그인이 일제히 "채널 핸들러 없음/connection 불가"면 개별
  버그가 아니라 **플러그인 등록 자체**를 우선 의심한다. v2 임베딩이라도 명시 등록을 둬 안전망 확보.

### 9.12 secure storage + 파일 폴백 동시 실패, 실제 예외가 가려짐
- **증상**: 9.11 수정(타임아웃 + 파일 폴백) APK에서 버튼 멈춤은 해소됐으나, 키 저장 시
  "키 저장 실패: Exception: 보안 저장소와 폴백 저장소를 모두 사용할 수 없습니다." 표시.
  즉 secure storage도, `getApplicationSupportDirectory()` 파일 폴백도 이 기기에서 실패.
- **원인**: Android 스캐폴딩(MainActivity=FlutterActivity v2, manifest flutterEmbedding=2,
  R8 비활성, GeneratedPluginRegistrant 정상 등록)은 정상 → MissingPluginException(등록
  누락)이 아니라 **기기별 실제 런타임 예외**. 그런데 코드가 그 예외 타입/메시지를 버리고
  일반 문구만 보여줘 원인 특정 불가.
- **해결**: (1) keystore/디렉터리에 비의존적인 **SharedPreferences** 저장 계층 추가
  (secure storage → SharedPreferences → 파일 순). (2) 파일 폴백 디렉터리를
  support→documents→temp 후보로 다중화. (3) 전부 실패 시 각 계층의 **실제 예외
  타입+짧은 메시지**(키 미포함, 120자 제한)를 모아 던져 스낵바로 노출.
- **재발 방지**: 폴백은 "성공/실패"만 반환하지 말고 **실패 원인 자체를 표면화**해야 진단
  가능하다. 영속 데이터는 단일 native 플러그인에 의존하지 말고 가장 호환성 높은 계층을 둔다.

### 9.11 secure storage write/read가 예외 없이 무한 대기(기기별)
- **증상**: 실기기에서 "키 저장" 후 버튼이 "저장 중…"에서 멈추고, 9.10의 try-catch를 적용한
  최신 APK를 재설치했는데도 **오류 스낵바조차 뜨지 않음**. 상단 "키가 설정되지 않았습니다"도
  녹색으로 바뀌지 않음.
- **원인**: 일부 Android 기기(Keystore/EncryptedSharedPreferences 초기화 이슈)에서
  `flutter_secure_storage`의 `write`/`read`가 **예외도 던지지 않고 완료도 되지 않는 무한 대기**
  상태가 됨. `await`가 끝나지 않으니 `finally`도 실행되지 않아 로딩 상태가 영구히 유지됨.
  try-catch만으로는(예외가 없으므로) 구제 불가.
- **해결**: `secrets.dart`의 모든 secure storage 호출에 `.timeout(5s)`를 걸어 UI가 반드시
  복구되게 하고, 실패/타임아웃 시 **앱 전용(샌드박스) 파일**(`getApplicationSupportDirectory`)로
  폴백 저장·조회. `AndroidOptions(resetOnError: true)`로 손상된 keystore 항목 자동 초기화.
- **재발 방지**: 플랫폼 채널/플러그인 호출은 try-catch뿐 아니라 **타임아웃**도 필수로 건다
  ("절대 끝나지 않는" 호출 대비). 핵심 영속 데이터는 단일 저장소에 의존하지 말고 폴백 경로를 둔다.

### 9.10 설정 화면 API 키 저장이 "저장 중…"에서 무한 대기
- **증상**: 실기기 release APK에서 API 키 입력 후 "키 저장" 클릭 시 버튼이 "저장 중…"
  상태로 멈추고, 위쪽 "키가 설정되지 않았습니다" 문구도 바뀌지 않음.
- **원인**: `settings_screen.dart`의 `_saveKey()`가 `await secretsProvider.setApiKey(key)`
  (flutter_secure_storage 쓰기)를 **try-catch 없이** 호출. 기기에서 secure storage 쓰기가
  예외를 던지면(Android Keystore 접근 실패 등) `setState(() => _saving = false)`가 실행되지
  않아 버튼이 영구히 비활성 상태로 남고, 사용자는 어떤 오류인지 전혀 알 수 없음.
- **해결**: `try/catch/finally`로 감싸 실패 시 스낵바로 실제 예외 메시지를 노출하고,
  `finally`에서 `_saving`을 항상 복구.
- **재발 방지**: 플러그인(secure storage 등 플랫폼 채널) 호출은 항상 try-catch로 감싸고,
  실패를 사용자에게 보이는 형태로 노출한다. "저장 중…" 류 로딩 상태는 반드시 finally에서 해제.

### 9.1 `ffmpeg_kit_flutter` 의존성 해석 실패(폐기됨)
- **증상**: 원본 패키지가 2025년 폐기되어 바이너리(Maven/CocoaPods) 제거, 설치 불가.
- **원인**: 저자가 프로젝트 아카이브, 릴리스 바이너리 내림.
- **해결**: 유지보수 포크 `ffmpeg_kit_flutter_new` 사용.
- **재발 방지**: 추출 관련 패키지는 유지보수 상태 확인 후 채택, 버전 핀 고정.

### 9.2 `require_trailing_commas` 린트 ↔ `dart format` 충돌
- **증상**: 포맷 후에도 trailing comma 경고가 반복 발생.
- **원인**: 커스텀 린트가 포맷터의 줄바꿈 판단과 충돌.
- **해결**: `analysis_options.yaml`에서 `require_trailing_commas` 제거(포맷터에 위임).
- **재발 방지**: 포맷터와 겹치는 스타일 린트는 켜지 않는다.

### 9.3 const 생성자의 `Duration` 비교 assert가 const 평가 불가
- **증상**: `const SubtitleCue(...)`/`const TranscriptSegment(...)` 컴파일 오류
  ("`>=` can't be invoked on Duration in a constant expression").
- **원인**: 생성자 `assert(end >= start)`의 `Duration.>=`는 컴파일 타임 평가 불가라
  const **컨텍스트** 사용 시 실패(생성자 선언 자체는 합법, 런타임 생성은 정상).
- **해결**: 해당 객체를 **const 컨텍스트에서 생성하지 않음**(테스트에서 `final` 사용).
  유효성 assert는 런타임 검증으로 유지.
- **재발 방지**: 생성자 assert에 비-const 연산(Duration 비교 등)이 있으면 `const` 인스턴스화 금지.

### 9.4 `File.readAsBytes` 오버라이드 반환형 불일치
- **증상**: 테스트용 `Fake` File에서 `Future<List<int>>` 반환 시 컴파일 오류.
- **원인**: `File.readAsBytes()`의 실제 반환형은 `Future<Uint8List>`.
- **해결**: `Uint8List.fromList(...)` 반환(`dart:typed_data`).
- **재발 방지**: dart:io API 오버라이드 시 정확한 반환형 확인.

### 9.5 `http.Response`가 비-ASCII 바디를 latin1로 인코딩해 실패
- **증상**: MockClient가 한글 포함 JSON을 응답하면
  "Invalid argument (string): Contains invalid characters".
- **원인**: `content-type`에 charset 미지정 시 `http`가 기본 latin1로 인코딩.
- **해결**: 응답 헤더에 `content-type: application/json; charset=utf-8` 지정.
- **재발 방지**: 다국어 응답 테스트는 항상 utf-8 charset 명시(실 Google 응답은 utf-8).

### 9.6 `mocktail` `any()`에 커스텀 타입 fallback 미등록
- **증상**: `any()`로 `File` 인자 매칭 시 런타임 오류.
- **원인**: 비-기본 타입은 `registerFallbackValue` 필요.
- **해결**: `setUpAll(() => registerFallbackValue(_FakeFile()))`.
- **재발 방지**: 커스텀 타입 `any()` 사용 전 fallback 등록.

### 9.7 (환경) 컨테이너에 Flutter 미설치
- **증상**: `flutter`/`dart` 명령 없음.
- **원인**: 원격 컨테이너 기본 이미지에 SDK 미포함.
- **해결**: Flutter SDK(stable) 다운로드·압축 해제 후 PATH 설정해 analyze/test 수행.
- **재발 방지**: 세션 시작 시 SDK 가용성 확인. 실기기 검증은 별도 환경 필요.

### 9.9 `ffmpeg_kit_flutter_new` 1.x Android 컴파일 실패(심볼 누락)
- **증상**: `flutter build apk`에서 `ffmpeg_kit_flutter_android-1.7.0` 컴파일 중
  `cannot find symbol: MediaInformationSession/MediaInformation/FFmpegKitConfig` 등 194개 에러.
  (`analyze`/`test`는 통과 → Dart 코드 문제 아님, 네이티브 의존성 문제.)
- **원인**: 1.x가 끌어오는 android 플러그인이 원본 arthenica AAR 바이너리에 의존하는데
  해당 바이너리가 Maven에서 제거되어 클래스 미해결.
- **해결**: `ffmpeg_kit_flutter_new`를 **4.2.1**로 상향(`^4.2.1`). Dart API
  (`executeWithArguments`/`getReturnCode`/`ReturnCode.isSuccess`/`getAllLogsAsString`)는 동일하게 동작.
  요구사항: Android API 24+(충족), **Kotlin 1.8.22+**(현재 settings.gradle 1.8.22 충족).
- **재발 방지**: 네이티브 바이너리 의존 패키지는 **유지보수 중인 최신 메이저**를 사용하고,
  CI에서 `flutter build apk`까지 돌려 네이티브 컴파일을 검증한다(analyze/test만으론 불충분).

### 9.8 Android minSdk가 ffmpeg 요구치 미달
- **증상**: Android 빌드 시 `ffmpeg_kit_flutter_new`가 요구하는 minSdk 미달로 manifest 병합 실패
  ("uses-sdk:minSdkVersion ... cannot be smaller than version 24 declared in library").
- **원인**: `android/app/build.gradle`의 `minSdk = flutter.minSdkVersion`(기본 21)이
  ffmpeg 라이브러리 요구치(24)보다 낮음.
- **해결**: `minSdk = 24`로 고정.
- **재발 방지**: 네이티브 바이너리 의존성 추가 시 각 라이브러리의 minSdk 요구치를 확인하고
  `app/build.gradle`에 명시적으로 반영.
