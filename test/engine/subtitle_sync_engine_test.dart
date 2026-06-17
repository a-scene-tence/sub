import 'package:flutter_test/flutter_test.dart';
import 'package:video_subtitle_translator/engine/subtitle_sync_engine.dart';
import 'package:video_subtitle_translator/models/subtitle_cue.dart';

SubtitleCue cue(int startMs, int endMs, String text) => SubtitleCue(
      start: Duration(milliseconds: startMs),
      end: Duration(milliseconds: endMs),
      text: text,
    );

void main() {
  group('SubtitleSyncEngine.cueAt', () {
    final cues = <SubtitleCue>[
      cue(0, 1000, 'A'),
      cue(1000, 2000, 'B'), // 인접(경계 공유)
      cue(3000, 4000, 'C'), // 2000~3000은 gap
    ];

    test('빈 큐는 항상 null', () {
      final engine = SubtitleSyncEngine(const <SubtitleCue>[]);
      expect(engine.cueAt(Duration.zero), isNull);
      expect(engine.cueAt(const Duration(seconds: 5)), isNull);
    });

    test('구간 시작은 포함, 종료는 제외', () {
      final engine = SubtitleSyncEngine(cues);
      // start == position -> 활성
      expect(engine.cueAt(Duration.zero)?.text, 'A');
      // 중간
      expect(engine.cueAt(const Duration(milliseconds: 500))?.text, 'A');
      // end == position -> 다음 큐(경계 공유 시 B)
      expect(engine.cueAt(const Duration(milliseconds: 1000))?.text, 'B');
    });

    test('gap 구간은 null', () {
      final engine = SubtitleSyncEngine(cues);
      expect(engine.cueAt(const Duration(milliseconds: 2500)), isNull);
    });

    test('첫 큐 이전과 마지막 큐 이후는 null', () {
      final engine = SubtitleSyncEngine(<SubtitleCue>[cue(1000, 2000, 'X')]);
      expect(engine.cueAt(const Duration(milliseconds: 500)), isNull);
      expect(engine.cueAt(const Duration(milliseconds: 2000)), isNull);
      expect(engine.cueAt(const Duration(milliseconds: 5000)), isNull);
    });

    test('되감기(backward seek)도 정확히 선택 — 캐시가 아닌 이진탐색', () {
      final engine = SubtitleSyncEngine(cues);
      // 순방향으로 C까지 이동(캐시 인덱스가 앞으로 감)
      expect(engine.cueAt(const Duration(milliseconds: 3500))?.text, 'C');
      // 되감기
      expect(engine.cueAt(const Duration(milliseconds: 500))?.text, 'A');
      expect(engine.cueAt(const Duration(milliseconds: 1500))?.text, 'B');
    });

    test('양수 offset은 자막을 미리 표시', () {
      // offset 200ms -> 실제 위치보다 200ms 이른 자막이 보임
      final engine = SubtitleSyncEngine(
        <SubtitleCue>[cue(1000, 2000, 'B')],
        offset: const Duration(milliseconds: 200),
      );
      // position 900ms - offset 200ms = query 700ms -> 아직 B 이전
      expect(engine.cueAt(const Duration(milliseconds: 900)), isNull);
      // position 1100ms - 200 = 900ms... 여전히 B 이전
      expect(engine.cueAt(const Duration(milliseconds: 1100)), isNull);
      // position 1300ms - 200 = 1100ms -> B 활성
      expect(engine.cueAt(const Duration(milliseconds: 1300))?.text, 'B');
    });

    test('정렬되지 않은/중첩 큐는 assert 발생', () {
      expect(
        () => SubtitleSyncEngine(<SubtitleCue>[
          cue(1000, 3000, 'A'),
          cue(2000, 4000, 'B'), // 중첩
        ]),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
