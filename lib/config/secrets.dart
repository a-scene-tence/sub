import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Google Cloud API 키 공급자.
///
/// 우선순위(읽기): (1) secure storage, (2) SharedPreferences,
/// (3) 앱 전용(샌드박스) 파일, (4) 빌드 시 `.env`의 `GOOGLE_API_KEY`.
///
/// 보안 규칙: 키를 로그·예외 메시지에 노출하지 않는다. `.env`/서비스계정 JSON은 커밋 금지.
/// 모바일 바이너리의 키는 추출 가능하므로 Cloud Console에서 API/앱ID로 제한할 것.
///
/// 일부 기기는 secure storage(keystore)도, 파일 디렉터리 조회도 실패한다(9.12).
/// 따라서 모든 native 호출에 [_ioTimeout]을 걸고, keystore에 비의존적인
/// SharedPreferences를 포함한 다층 폴백으로 저장하며, 전부 실패하면 각 계층의
/// **실제 예외 타입/메시지**를 모아 던져 원인을 진단할 수 있게 한다.
class Secrets {
  Secrets({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(resetOnError: true),
            );

  final FlutterSecureStorage _storage;

  static const String _storageKey = 'google_api_key';

  /// native 호출이 무한 대기하는 기기 대비 타임아웃.
  static const Duration _ioTimeout = Duration(seconds: 5);

  /// 파일 폴백 파일명.
  static const String _fallbackFileName = 'google_api_key.txt';

  /// 유효한 API 키를 반환한다. 없으면 null.
  Future<String?> getApiKey() async {
    // 1) secure storage
    try {
      final stored =
          await _storage.read(key: _storageKey).timeout(_ioTimeout);
      if (stored != null && stored.trim().isNotEmpty) return stored.trim();
    } catch (_) {
      // 다음 계층으로 진행
    }

    // 2) SharedPreferences
    try {
      final prefs =
          await SharedPreferences.getInstance().timeout(_ioTimeout);
      final v = prefs.getString(_storageKey)?.trim();
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {
      // 다음 계층으로 진행
    }

    // 3) 파일 폴백
    final fromFile = await _readFile();
    if (fromFile != null && fromFile.isNotEmpty) return fromFile;

    // 4) 빌드 시 .env
    final fromEnv = _envKey();
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
    return null;
  }

  /// 런타임 입력 키를 저장한다. 계층을 순서대로 시도하고, 전부 실패하면
  /// 각 계층의 실제 예외를 모은 진단 메시지로 예외를 던진다(키 문자열 미포함).
  Future<void> setApiKey(String key) async {
    final trimmed = key.trim();
    final errors = <String>[];

    // 1) secure storage
    try {
      await _storage
          .write(key: _storageKey, value: trimmed)
          .timeout(_ioTimeout);
      // 성공 시 다른 폴백은 정리(혼선 방지).
      await _clearPrefs();
      await _deleteFile();
      return;
    } catch (e) {
      errors.add('secure: ${_describe(e)}');
    }

    // 2) SharedPreferences
    try {
      final prefs =
          await SharedPreferences.getInstance().timeout(_ioTimeout);
      await prefs.setString(_storageKey, trimmed).timeout(_ioTimeout);
      return;
    } catch (e) {
      errors.add('prefs: ${_describe(e)}');
    }

    // 3) 파일 폴백
    try {
      await _writeFile(trimmed);
      return;
    } catch (e) {
      errors.add('file: ${_describe(e)}');
    }

    throw Exception('키 저장 실패(모든 저장소): ${errors.join(' / ')}');
  }

  /// 저장된 키 제거(모든 계층, best-effort).
  Future<void> clearApiKey() async {
    try {
      await _storage.delete(key: _storageKey).timeout(_ioTimeout);
    } catch (_) {/* best-effort */}
    await _clearPrefs();
    await _deleteFile();
  }

  // --- SharedPreferences 헬퍼 ------------------------------------------------

  Future<void> _clearPrefs() async {
    try {
      final prefs =
          await SharedPreferences.getInstance().timeout(_ioTimeout);
      await prefs.remove(_storageKey);
    } catch (_) {/* best-effort */}
  }

  // --- 앱 전용(샌드박스) 파일 폴백 -------------------------------------------
  // 디렉터리 조회는 기기별로 일부 메서드가 실패할 수 있어 후보를 순회한다.

  Future<File?> _fallbackFile() async {
    final candidates = <Future<Directory> Function()>[
      getApplicationSupportDirectory,
      getApplicationDocumentsDirectory,
      getTemporaryDirectory,
    ];
    for (final getDir in candidates) {
      try {
        final dir = await getDir().timeout(_ioTimeout);
        return File(p.join(dir.path, _fallbackFileName));
      } catch (_) {
        // 다음 후보 디렉터리 시도
      }
    }
    return null;
  }

  Future<String?> _readFile() async {
    try {
      final f = await _fallbackFile();
      if (f != null && await f.exists()) {
        final v = (await f.readAsString()).trim();
        return v.isEmpty ? null : v;
      }
    } catch (_) {/* best-effort */}
    return null;
  }

  Future<void> _writeFile(String key) async {
    final f = await _fallbackFile();
    if (f == null) {
      throw Exception('사용 가능한 앱 디렉터리를 찾지 못함');
    }
    await f.writeAsString(key, flush: true);
  }

  Future<void> _deleteFile() async {
    try {
      final f = await _fallbackFile();
      if (f != null && await f.exists()) await f.delete();
    } catch (_) {/* best-effort */}
  }

  /// 예외를 진단용 짧은 문자열로 변환한다. 키 문자열은 포함되지 않는
  /// 저장소/플랫폼 예외만 다루며, 길이를 제한해 과도한 노출을 막는다.
  static String _describe(Object e) {
    final s = e.toString().replaceAll('\n', ' ');
    const max = 120;
    final body = s.length > max ? '${s.substring(0, max)}…' : s;
    return '${e.runtimeType}: $body';
  }

  static String? _envKey() {
    // dotenv 미초기화 시 예외가 날 수 있으므로 방어적으로 접근.
    try {
      final v = dotenv.maybeGet('GOOGLE_API_KEY');
      return (v == null || v.trim().isEmpty) ? null : v.trim();
    } catch (_) {
      return null;
    }
  }
}
