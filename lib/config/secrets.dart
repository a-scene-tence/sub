import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Google Cloud API 키 공급자.
///
/// 우선순위: (1) 런타임에 설정 화면에서 입력해 secure storage에 저장한 키,
/// (2) 빌드 시 `.env`의 `GOOGLE_API_KEY`.
///
/// 보안 규칙: 키를 로그로 출력하지 않는다. `.env`/서비스계정 JSON은 커밋 금지.
/// 모바일 바이너리의 키는 추출 가능하므로 Cloud Console에서 API/앱ID로 제한할 것.
class Secrets {
  Secrets({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _storageKey = 'google_api_key';

  /// 유효한 API 키를 반환한다. 없으면 null.
  Future<String?> getApiKey() async {
    final stored = await _storage.read(key: _storageKey);
    if (stored != null && stored.trim().isNotEmpty) return stored.trim();

    final fromEnv = _envKey();
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
    return null;
  }

  /// 런타임 입력 키를 안전 저장.
  Future<void> setApiKey(String key) =>
      _storage.write(key: _storageKey, value: key.trim());

  Future<void> clearApiKey() => _storage.delete(key: _storageKey);

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
