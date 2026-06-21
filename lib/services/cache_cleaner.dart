import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 임시(캐시) 디렉터리에 쌓이는 우리 산출물을 정리한다.
///
/// 두 가지가 용량을 키운다: (1) `file_picker`가 선택한 영상 전체를 캐시로 복사한 사본
/// (`<temp>/file_picker/...`), (2) 오디오 추출 WAV(`audio_*.wav`). 둘 다 임시 디렉터리에
/// 생기므로 여기서만 지운다. **API 키 폴백 파일 등 다른 파일이나 사용자 원본은 건드리지 않는다.**
class CacheCleaner {
  CacheCleaner._();

  /// 앱 시작 시 잔여 임시 산출물 정리(강제 종료 등으로 남은 것 회수). best-effort.
  static Future<void> purgeOnStartup() => _purge();

  /// 수동 '캐시 비우기'. 시작 정리와 동일 범위.
  static Future<void> clearCache() => _purge();

  /// [filePath]가 임시 디렉터리 내부일 때만 삭제한다(사용자 원본 보호 가드).
  /// 재생 종료 시 file_picker 캐시 사본을 지우는 용도.
  static Future<void> deleteIfTemp(String filePath) async {
    try {
      final tmp = await getTemporaryDirectory();
      if (!p.isWithin(tmp.path, filePath)) return;
      final f = File(filePath);
      if (await f.exists()) await f.delete();
    } catch (_) {/* best-effort */}
  }

  /// 현재 임시 디렉터리 총 용량(바이트). 실패 시 0.
  static Future<int> cacheSizeBytes() async {
    try {
      final tmp = await getTemporaryDirectory();
      return _dirSize(tmp);
    } catch (_) {
      return 0;
    }
  }

  static Future<void> _purge() async {
    try {
      final tmp = await getTemporaryDirectory();
      for (final e in tmp.listSync()) {
        try {
          // 오디오 추출 WAV.
          if (e is File && p.basename(e.path).startsWith('audio_')) {
            e.deleteSync();
            continue;
          }
          // file_picker 영상 복사본 디렉터리.
          if (e is Directory && p.basename(e.path) == 'file_picker') {
            e.deleteSync(recursive: true);
          }
        } catch (_) {/* 개별 실패 무시 */}
      }
    } catch (_) {/* best-effort */}
  }

  static int _dirSize(Directory dir) {
    var total = 0;
    try {
      for (final e in dir.listSync(recursive: true, followLinks: false)) {
        if (e is File) {
          try {
            total += e.lengthSync();
          } catch (_) {/* 접근 불가 무시 */}
        }
      }
    } catch (_) {/* best-effort */}
    return total;
  }
}

/// 바이트를 사람이 읽기 쉬운 단위로(예: `12.3 MB`). 음수/0은 `0 B`.
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final str = unit == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return '$str ${units[unit]}';
}
