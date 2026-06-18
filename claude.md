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

### 9.8 Android minSdk가 ffmpeg 요구치 미달
- **증상**: Android 빌드 시 `ffmpeg_kit_flutter_new`가 요구하는 minSdk 미달로 manifest 병합 실패
  ("uses-sdk:minSdkVersion ... cannot be smaller than version 24 declared in library").
- **원인**: `android/app/build.gradle`의 `minSdk = flutter.minSdkVersion`(기본 21)이
  ffmpeg 라이브러리 요구치(24)보다 낮음.
- **해결**: `minSdk = 24`로 고정.
- **재발 방지**: 네이티브 바이너리 의존성 추가 시 각 라이브러리의 minSdk 요구치를 확인하고
  `app/build.gradle`에 명시적으로 반영.
