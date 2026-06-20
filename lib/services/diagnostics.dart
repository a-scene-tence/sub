import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 네이티브 크래시까지 추적하기 위한 "빵부스러기" 진단 기록기.
///
/// 각 위험 단계 **직전**에 [record]로 현재 단계를 파일에 즉시 flush 저장한다.
/// 앱이 네이티브로 강제 종료(SIGSEGV/OOM 등)되어도 마지막 기록이 디스크에 남으므로,
/// 재실행 후 [read]로 "마지막으로 도달한 단계"를 확인해 크래시 지점을 특정할 수 있다.
/// (Dart try-catch로 잡히지 않는 네이티브 크래시 진단용 — 폰만으로 로그 확보 불가 대응.)
class Diagnostics {
  Diagnostics._();

  static const String _fileName = 'last_breadcrumb.txt';

  static Future<File?> _file() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File(p.join(dir.path, _fileName));
    } catch (_) {
      return null;
    }
  }

  /// 현재 단계를 타임스탬프와 함께 디스크에 즉시(flush) 기록한다. best-effort.
  static Future<void> record(String step) async {
    try {
      final f = await _file();
      if (f == null) return;
      final line = '${DateTime.now().toIso8601String()} | $step';
      await f.writeAsString(line, flush: true);
    } catch (_) {/* best-effort */}
  }

  /// 마지막으로 기록된 단계를 읽는다. 없으면 null.
  static Future<String?> read() async {
    try {
      final f = await _file();
      if (f != null && await f.exists()) {
        final v = (await f.readAsString()).trim();
        return v.isEmpty ? null : v;
      }
    } catch (_) {/* best-effort */}
    return null;
  }

  /// 기록 삭제.
  static Future<void> clear() async {
    try {
      final f = await _file();
      if (f != null && await f.exists()) await f.delete();
    } catch (_) {/* best-effort */}
  }
}
