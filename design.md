# 앱 디자인 (design.md)

> 작업 진행에 따라 지속 업데이트.

## 1. 화면 구조 / 내비게이션

```
HomeScreen ──(파일 선택 / URL)──▶ PlayerScreen
   │                                   │
   └──(설정 아이콘)──▶ SettingsScreen ◀─┘
```

| 화면 | 파일 | 역할 |
|------|------|------|
| Home | `lib/screens/home_screen.dart` | 영상 파일 선택 / URL 입력 진입점 |
| Player | `lib/screens/player_screen.dart` | 영상 재생 + 자막 오버레이 + 처리 진행 표시 |
| Settings | `lib/screens/settings_screen.dart` | API 키, 대상 언어, 소스 언어 힌트, 원문 표시 |

## 2. 상태 흐름 (처리 파이프라인)

```
idle ─▶ extracting ─▶ recognizing ─▶ translating ─▶ ready ─▶ (재생)
                          │                              ▲
                          └──────────── error ───────────┘
```

- 상태는 `ProcessingStatus`(`lib/state/processing_controller.dart`)로 표현.
- `ready` 진입 시 `PlayerController.attach(...)`로 자막 큐를 연결하고 재생 시작.
- 각 비-종료 상태에서 `ProcessingIndicator`가 라벨과 스피너(또는 에러 아이콘)를 오버레이.

## 3. 주요 UI 컴포넌트

### 3.1 SubtitleOverlay (`lib/widgets/subtitle_overlay.dart`)
- 영상 위 **하단 중앙**에 자막 표시. 활성 큐가 없으면 아무것도 그리지 않음.
- 반투명 검정 배경 + 흰 글자(가독성). `showSource`가 켜지면 원문을 작게 위에 함께 표시.
- 활성 큐가 바뀔 때만 리빌드(`ValueListenableBuilder` + `PlayerController.activeCue`).

### 3.2 ProcessingIndicator (`lib/widgets/processing_indicator.dart`)
- 반투명 막 위에 단계 라벨("오디오 추출 중…", "음성 인식 중…", "번역 중…") + 스피너.
- 에러 시 에러 아이콘 + 메시지.

### 3.3 PlayerScreen 레이아웃
```
┌────────────── AppBar(재생, ⚙) ──────────────┐
│                                              │
│            ┌───────────────────┐             │
│            │   VideoPlayer      │  ← AspectRatio
│            │                    │             │
│            │   [ 자막 오버레이 ]  │  ← 하단 중앙
│            └───────────────────┘             │
│        [처리 인디케이터 — 준비 중에만]          │
│                                   (▶/⏸ FAB) │
└──────────────────────────────────────────────┘
```

## 4. 비주얼 가이드

- **테마**: Material 3, `ColorScheme.fromSeed(seedColor: #3B6EF6)`(블루).
- **플레이어 배경**: 검정(영상 몰입).
- **자막**: 글자 흰색 20sp/`w600`, 배경 검정 60% 불투명, 라운드 6.
  원문은 14sp/흰색 70%.
- **타이포**: 시스템 기본. 자막은 가독성 위해 `height: 1.3`.
- **아이콘**: Material Icons(`video_library`, `play_circle_outline`, `settings`, `pause`/`play_arrow`).

## 5. 인터랙션

- **Home**: "영상 파일 선택"(file picker) 또는 URL 입력 후 "URL 재생".
- **Player**: 자동 처리→재생. FAB로 재생/일시정지. ⚙로 설정 진입.
- **Settings**: 키 저장(obscure 입력), 대상 언어 드롭다운, 소스 언어(자동 감지/수동),
  "원문 함께 표시" 스위치. 변경은 다음 처리부터 반영.

## 6. 동기화 UX 설계 근거

- `video_player`는 고빈도 위치 스트림이 없어 ~10Hz 타이머로 위치를 폴링
  (`PlayerController.tick = 100ms`).
- 자막 선택은 `SubtitleSyncEngine`이 **이진탐색 + 직전 인덱스 캐시**로 처리 → 시킹/되감기 정확,
  순방향 재생은 빠른 경로.
- 추출/디코더 지연 보정을 위해 `SubtitleSyncEngine.offset`(기본 0) 제공 → 드리프트 튜닝 가능.

## 7. 접근성/향후

- 자막 폰트 크기·배경 투명도 사용자 설정(Phase 2).
- 자막 위치(상/하) 선택, 고대비 모드.
- 자막 SRT/VTT 내보내기.
