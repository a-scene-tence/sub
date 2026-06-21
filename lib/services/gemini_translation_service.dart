import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'language_codes.dart';
import 'translation_service.dart';

/// Gemini(생성형 언어 API) 기반 번역. 한 윈도우의 여러 줄을 함께 넘겨 문맥을 반영하고,
/// "자연스러운 구어체 자막"(한국어는 해요체)으로 번역한다. API 키 인증(쿼리 파라미터).
///
/// 입력과 동일한 개수·순서의 JSON 문자열 배열을 강제(`responseSchema`)해 세그먼트 1:1 정렬을
/// 견고하게 유지한다. 실패(키 미설정·쿼터·모델 미가용·형식 오류)는 [TranslationException]을
/// 던져 상위 폴백이 받아주게 한다.
class GeminiTranslationService implements TranslationService {
  GeminiTranslationService({
    required this.apiKey,
    this.model = AppConfig.geminiModel,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String apiKey;
  final String model;
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
    if (src != null && src.isNotEmpty && src == tgt) {
      return List<String>.from(texts);
    }

    final body = <String, dynamic>{
      'systemInstruction': <String, dynamic>{
        'parts': <Map<String, String>>[
          {'text': buildGeminiInstruction(target: tgt, source: src)},
        ],
      },
      'contents': <Map<String, dynamic>>[
        {
          'role': 'user',
          'parts': <Map<String, String>>[
            {'text': jsonEncode(texts)},
          ],
        },
      ],
      'generationConfig': <String, dynamic>{
        'responseMimeType': 'application/json',
        'responseSchema': <String, dynamic>{
          'type': 'ARRAY',
          'items': <String, String>{'type': 'STRING'},
        },
        'temperature': 0.3,
        // 비용 최소화: 자막 번역엔 추론(thinking)이 불필요하다. gemini-2.5-flash는
        // 기본적으로 thinking이 켜져 있고 그 토큰이 '출력' 단가로 과금되며 지연도 늘린다.
        // 0으로 꺼서 토큰·비용·지연을 모두 줄인다.
        'thinkingConfig': <String, dynamic>{'thinkingBudget': 0},
        // 출력 상한: 번역문은 입력과 비슷한 길이이므로, 정상 번역은 잘리지 않을 만큼
        // 넉넉히 두되 비정상적인 폭주 응답의 비용을 막는다.
        'maxOutputTokens': _maxOutputTokensFor(texts),
      },
    };

    final uri = Uri.parse('${AppConfig.geminiGenerateUrl(model)}?key=$apiKey');
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
          'Gemini 번역 실패 (HTTP ${resp.statusCode}): ${_errorMessage(resp.body)}');
    }

    return parseGeminiTranslateResponse(resp.body, expected: texts.length);
  }

  /// 출력 토큰 상한을 입력 길이에 비례해 넉넉히 잡는다. 토큰≈문자수의 보수적 배수에
  /// 여유분을 더해, 정상 번역은 절대 잘리지 않으면서 폭주 비용만 차단한다.
  static int _maxOutputTokensFor(List<String> texts) {
    final chars = texts.fold<int>(0, (sum, t) => sum + t.length);
    return chars * 3 + 512;
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

/// Gemini 번역에 쓸 시스템 지시문을 만든다(순수 함수, 테스트 대상).
/// [target]/[source]는 ISO-639-1 코드. 한국어 대상이면 해요체를 일관되게 요구한다.
String buildGeminiInstruction({required String target, String? source}) {
  final targetName = languageDisplayName(target);
  final lines = <String>[
    'You are a professional video subtitle translator. '
        'Translate each line of the input JSON array into $targetName.',
    '- Produce natural, colloquial, conversational subtitles as a native '
        'speaker would actually say them — NOT a literal word-for-word translation.',
  ];
  if (target == 'ko') {
    lines.add(
        '- For Korean, use a natural, polite conversational register (해요체) '
        'consistently across all lines.');
  }
  if (source != null && source.isNotEmpty) {
    lines.add('- The source language is ${languageDisplayName(source)}.');
  }
  lines.addAll(<String>[
    '- Keep each translation concise and readable as on-screen subtitles.',
    '- Output ONLY a JSON array of strings with EXACTLY the same number of '
        'elements and the same order as the input. Do not merge, split, add, or '
        'drop lines. If a line cannot be translated, return it unchanged.',
  ]);
  return lines.join('\n');
}

/// Gemini generateContent 응답에서 번역문 리스트를 파싱(순수 함수, 테스트 대상).
/// 후보 텍스트(JSON 배열, 드물게 ```json 펜스 포함)를 디코드해 [expected] 길이로 검증한다.
List<String> parseGeminiTranslateResponse(String responseBody,
    {required int expected}) {
  final Map<String, dynamic> json;
  try {
    json = jsonDecode(responseBody) as Map<String, dynamic>;
  } catch (e) {
    throw TranslationException('Gemini 응답 JSON 파싱 실패: $e');
  }

  final candidates = json['candidates'];
  if (candidates is! List || candidates.isEmpty) {
    throw TranslationException('Gemini 응답에 후보가 없음');
  }
  final content = (candidates.first as Map)['content'];
  final parts = content is Map ? content['parts'] : null;
  if (parts is! List || parts.isEmpty) {
    throw TranslationException('Gemini 응답 형식 오류');
  }

  final buffer = StringBuffer();
  for (final p in parts) {
    if (p is Map && p['text'] is String) buffer.write(p['text'] as String);
  }
  final text = _stripJsonFence(buffer.toString().trim());

  final List<dynamic> decoded;
  try {
    decoded = jsonDecode(text) as List<dynamic>;
  } catch (e) {
    throw TranslationException('Gemini 번역 배열 파싱 실패: $e');
  }

  final out = decoded.map((e) => e?.toString() ?? '').toList();
  if (out.length != expected) {
    throw TranslationException(
        'Gemini 번역 결과 개수 불일치(기대 $expected, 실제 ${out.length})');
  }
  return out;
}

/// 응답이 ```json … ``` 펜스로 감싸진 경우 안쪽 JSON만 남긴다.
String _stripJsonFence(String s) {
  if (!s.startsWith('```')) return s;
  var t = s.substring(3);
  if (t.toLowerCase().startsWith('json')) t = t.substring(4);
  final end = t.lastIndexOf('```');
  if (end != -1) t = t.substring(0, end);
  return t.trim();
}
