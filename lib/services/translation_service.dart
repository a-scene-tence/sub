import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'language_codes.dart';

class TranslationException implements Exception {
  TranslationException(this.message);
  final String message;
  @override
  String toString() => 'TranslationException: $message';
}

/// 텍스트 번역 추상 인터페이스.
abstract class TranslationService {
  /// [texts]를 [target] 언어로 번역(배치). [source]가 null이면 자동 감지.
  /// 입력과 동일한 순서·길이의 결과를 반환한다.
  Future<List<String>> translateBatch(
    List<String> texts, {
    required String target,
    String? source,
  });
}

/// Google Cloud Translation API v2(Basic) 구현. API 키 인증.
class GoogleTranslationService implements TranslationService {
  GoogleTranslationService({
    required this.apiKey,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  @override
  Future<List<String>> translateBatch(
    List<String> texts, {
    required String target,
    String? source,
  }) async {
    if (texts.isEmpty) return <String>[];

    final tgt = toIsoLanguage(target);
    final src = source == null ? null : toIsoLanguage(source);

    // 원문 언어 == 대상 언어면 번역 불필요(쿼터/비용 절감).
    if (src != null && src == tgt) return List<String>.from(texts);

    final body = <String, dynamic>{
      'q': texts,
      'target': tgt,
      'format': 'text',
      if (src != null && src.isNotEmpty) 'source': src,
    };

    final uri = Uri.parse('${AppConfig.translateV2Url}?key=$apiKey');
    final http.Response resp;
    try {
      resp = await _client.post(
        uri,
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
    } catch (e) {
      throw TranslationException('네트워크 오류: $e');
    }

    if (resp.statusCode != 200) {
      throw TranslationException(
          '번역 실패 (HTTP ${resp.statusCode}): ${_errorMessage(resp.body)}');
    }

    return parseTranslateResponse(resp.body, expected: texts.length);
  }

  String _errorMessage(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final error = json['error'];
      if (error is Map && error['message'] is String) {
        return error['message'] as String;
      }
    } catch (_) {/* ignore */}
    return '응답을 해석할 수 없음';
  }
}

/// Translation v2 응답을 번역문 리스트로 파싱(순수 함수, 테스트 대상).
/// HTML 엔티티(`&#39;` 등)를 디코드한다.
List<String> parseTranslateResponse(String responseBody,
    {required int expected}) {
  final Map<String, dynamic> json;
  try {
    json = jsonDecode(responseBody) as Map<String, dynamic>;
  } catch (e) {
    throw TranslationException('번역 응답 JSON 파싱 실패: $e');
  }

  final data = json['data'];
  final translations = data is Map ? data['translations'] : null;
  if (translations is! List) {
    throw TranslationException('번역 응답 형식 오류');
  }

  final out = <String>[];
  for (final t in translations) {
    if (t is Map && t['translatedText'] is String) {
      out.add(_decodeHtmlEntities(t['translatedText'] as String));
    } else {
      out.add('');
    }
  }

  if (out.length != expected) {
    throw TranslationException('번역 결과 개수 불일치(기대 $expected, 실제 ${out.length})');
  }
  return out;
}

/// Translation v2가 반환하는 기본 HTML 엔티티를 평문으로 디코드.
String _decodeHtmlEntities(String input) {
  return input
      .replaceAll('&#39;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ');
}
