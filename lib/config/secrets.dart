import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Google Cloud API 키 공급자.
///
/// 우선순위: (1) 런타임에 설정 화면에서 입력해 secure storage에 저장한 키,
/// (2) secure storage 장애 시 앱 전용(샌드박스) 파일 폴백, (3) 빌드 시 `.env`의 `GOOGLE_API_KEY`.
///
/// 보안 규칙: 키를 로그로 출력하지 않는다. `.env`/서비스계정 JSON은 커밋 금지.
/// 모바일 바이너리의 키는 추출 가능하므로 Cloud Console에서 API/앱ID로 제한할 것.
///
/// 일부 기기는 Android Keystore/EncryptedSharedPreferences 초기화가 예외도 없이
/// 무한 블로킹된다(9.11). 따라서 모든 secure storage 호출에 [_ioTimeout]을 걸어
/// UI가 반드시 복구되게 하고, 실패/타임아웃 시 파일 폴백으로 저장한다.
class Secrets {
  Secrets({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(resetOnError: true),
            );

  final FlutterSecureStorage _storage;

  static const String _storageKey = 'google_api_key';

  /// secure storage 호출이 무한 대기하는 기기 대비 타임아웃.
  static const Duration _ioTimeout = Duration(seconds: 5);

  /// secure storage 불가 시 사용하는 앱 전용 디렉터리 폴백 파일명.
  static const String _fallbackFileName = 'google_api_key.txt';

  /// 유효한 API 키를 반환한다. 없으면 null.
  Future<String?> getApiKey() async {
    // 1) secure storage (타임아웃/예외 시 폴백으로 진행)
    try {
      final stored =
          await _storage.read(key: _storageKey).timeout(_ioTimeout);
      if (stored != null && stored.trim().isNotEmpty) return stored.trim();
    } catch (_) {
      // keystore 장애/타임아웃 → 아래 폴백으로 진행
    }

    // 2) 파일 폴백(기기 keystore 장애 대비)
    final fromFile = await _readFallback();
    if (fromFile != null && fromFile.isNotEmpty) return fromFile;

    // 3) 빌드 시 .env
    final fromEnv = _envKey();
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
    return null;
  }

  /// 런타임 입력 키를 저장한다. secure storage가 실패/무한대기면 파일 폴백에 저장.
  Future<void> setApiKey(String key) async {
    final trimmed = key.trim();
    try {
      await _storage
          .write(key: _storageKey, value: trimmed)
          .timeout(_ioTimeout);
      // secure storage에 성공적으로 저장했으면 폴백 파일은 정리.
      await _deleteFallback();
      return;
    } catch (_) {
      // secure storage 실패/타임아웃 → 파일 폴백에 저장(실패 시 예외 전파).
      await _writeFallback(trimmed);
    }
  }

  /// 저장된 키 제거(secure storage + 폴백 파일 모두).
  Future<void> clearApiKey() async {
    try {
      await _storage.delete(key: _storageKey).timeout(_ioTimeout);
    } catch (_) {
      // best-effort
    }
    await _deleteFallback();
  }

  // --- 앱 전용(샌드박스) 파일 폴백 -------------------------------------------
  // getApplicationSupportDirectory()는 앱 전용 디렉터리로 외부 앱이 접근 불가.
  // 테스트/미지원 환경에서는 디렉터리 획득이 실패할 수 있으므로 방어적으로 처리.

  Future<File?> _fallbackFile() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File(p.join(dir.path, _fallbackFileName));
    } catch (_) {
      return null;
    }
  }

  Future<String?> _readFallback() async {
    try {
      final f = await _fallbackFile();
      if (f != null && await f.exists()) {
        final v = (await f.readAsString()).trim();
        return v.isEmpty ? null : v;
      }
    } catch (_) {
      // best-effort
    }
    return null;
  }

  Future<void> _writeFallback(String key) async {
    final f = await _fallbackFile();
    if (f == null) {
      throw Exception('보안 저장소와 폴백 저장소를 모두 사용할 수 없습니다.');
    }
    await f.writeAsString(key, flush: true);
  }

  Future<void> _deleteFallback() async {
    try {
      final f = await _fallbackFile();
      if (f != null && await f.exists()) await f.delete();
    } catch (_) {
      // best-effort
    }
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
