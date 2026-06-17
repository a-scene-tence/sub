# 영상 번역 자막 앱 (Video Subtitle Translator)

모바일에서 앱 내 영상(로컬 파일 / URL)을 재생할 때, 영상 속 음성의 **언어를 자동 인식**하고
**실시간으로 번역**하여 재생과 동기화된 **자막을 자동으로** 띄워주는 Flutter 앱.

- **플랫폼**: Flutter (iOS / Android 크로스플랫폼)
- **음성 인식 / 언어 감지**: Google Cloud Speech-to-Text
- **번역**: Google Cloud Translation API (v2 Basic)
- **자막 동기화**: 추출된 자막 큐를 `video_player` 재생 위치에 맞춰 표시

## 문서

| 파일 | 내용 |
|------|------|
| [`spec.md`](spec.md) | 기획서 — 제품 목표, 요구사항, 범위, 마일스톤 |
| [`claude.md`](claude.md) | 개발 규칙·제약사항 + **버그/오류 로그** (재발 방지) |
| [`design.md`](design.md) | 앱 디자인 — 화면 구조, UI, 상태 흐름 |

## 동작 파이프라인

```
영상 로드 → 오디오 추출(16kHz mono WAV) → Google STT(전사+타임스탬프+언어감지)
        → 세그먼트 번역 → 자막 큐 생성 → 재생 위치 동기화 표시
```

## 프로젝트 구조

```
lib/
  main.dart, app.dart
  config/      app_config.dart, secrets.dart
  models/      subtitle_cue.dart, transcript_segment.dart, recognition_result.dart
  services/    audio_extraction_service.dart, speech_service.dart,
               translation_service.dart, cue_builder.dart
  engine/      subtitle_sync_engine.dart      # 순수 Dart 동기화 로직
  state/       player_controller.dart, processing_controller.dart
  screens/     home_screen.dart, player_screen.dart, settings_screen.dart
  widgets/     subtitle_overlay.dart, processing_indicator.dart
test/          engine/, models/, services/    # 단위 테스트
```

## 셋업

1. Flutter SDK 설치 (3.x 이상).
2. 의존성 설치:
   ```bash
   flutter pub get
   ```
3. Google Cloud API 키 준비 (Speech-to-Text + Translation Basic 활성화):
   ```bash
   cp .env.example .env
   # .env 파일에 GOOGLE_API_KEY=발급받은_키 입력  (절대 커밋 금지)
   ```
   런타임에는 설정 화면에서 직접 키를 입력해 안전 저장(secure storage)할 수도 있습니다.
4. 실행:
   ```bash
   flutter run
   ```

## 검증

```bash
flutter analyze   # 정적 분석
flutter test      # 단위 테스트 (동기화 엔진·모델·서비스 로직)
```

> ⚠️ MVP 범위: 인라인 STT 60초 제한으로 **≤60초 클립** 권장.
> 장편(GCS + longRunningRecognize)은 Phase 2 (인터페이스 뒤 스텁).
