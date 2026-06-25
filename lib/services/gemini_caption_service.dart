import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/subtitle_cue.dart';
import 'language_codes.dart';

/// 캡션(전사+번역) 실패를 알리는 예외.
class CaptionException implements Exception {
  CaptionException(this.message, {this.statusCode, this.retryAfter});
  final String message;

  /// HTTP 상태 코드(있으면). 429면 호출자가 한도 초과로 백오프한다.
  final int? statusCode;

  /// 서버가 안내한 재시도 대기 시간(429의 Retry-After/RetryInfo, 있으면).
  final Duration? retryAfter;

  @override
  String toString() => 'CaptionException: $message';
}

/// 오디오 윈도우를 받아 (윈도우 기준 상대 타임스탬프의) 자막 큐를 반환하는 추상화.
/// 구현체는 [CueBuilder]나 별도 STT 없이도 큐를 만들 수 있다(라이브 파이프라인 테스트 시 목 대체).
abstract class CaptionSource {
  Future<List<SubtitleCue>> caption(
    List<int> audioBytes, {
    required String targetLanguage,
    String? languageHint,
  });
}

/// Gemini 멀티모달 **단일 호출**로 오디오를 전사+번역해 자막 큐를 만든다.
///
/// 16kHz mono WAV를 인라인으로 보내고, 문장/절 단위 `{start,end,source,text}` 세그먼트(JSON)를
/// 받는다. `start`/`end`는 이 클립 시작 기준 초이며, 호출자가 윈도우 시작만큼 밀어 영상 시각에
/// 맞춘다. Google Cloud STT/Translation 없이 Gemini 키 하나로 동작한다.
class GeminiCaptionService implements CaptionSource {
  GeminiCaptionService({
    required this.apiKey,
    this.model = AppConfig.geminiModel,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String apiKey;
  final String model;
  final http.Client _client;

  @override
  Future<List<SubtitleCue>> caption(
    List<int> audioBytes, {
    required String targetLanguage,
    String? languageHint,
  }) async {
    if (audioBytes.isEmpty) return <SubtitleCue>[];

    final tgt = toIsoLanguage(targetLanguage);
    final body = <String, dynamic>{
      'systemInstruction': <String, dynamic>{
        'parts': <Map<String, String>>[
          {
            'text': buildGeminiCaptionInstruction(
                target: tgt, languageHint: languageHint),
          },
        ],
      },
      'contents': <Map<String, dynamic>>[
        {
          'role': 'user',
          'parts': <Map<String, dynamic>>[
            {
              'inlineData': <String, String>{
                'mimeType': 'audio/wav',
                'data': base64Encode(audioBytes),
              },
            },
            {'text': 'Transcribe and translate this audio clip.'},
          ],
        },
      ],
      'generationConfig': <String, dynamic>{
        'responseMimeType': 'application/json',
        'responseSchema': _captionSchema,
        'temperature': 0.2,
        // 비용/지연 최소화: 자막에는 추론(thinking) 불필요.
        'thinkingConfig': <String, dynamic>{'thinkingBudget': 0},
        'maxOutputTokens': _maxOutputTokensFor(audioBytes.length),
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
      throw CaptionException('네트워크 오류: $e');
    }

    if (resp.statusCode != 200) {
      throw CaptionException(
        'Gemini 캡션 실패 (HTTP ${resp.statusCode}): ${_errorMessage(resp.body)}',
        statusCode: resp.statusCode,
        retryAfter: _parseRetryAfter(resp),
      );
    }

    return parseGeminiCaptionResponse(resp.body);
  }

  /// 429 등의 재시도 대기 시간을 찾는다. Retry-After 헤더 → 본문 RetryInfo.retryDelay
  /// → 메시지의 "retry in Xs" 순으로 해석한다. 없으면 null.
  Duration? _parseRetryAfter(http.Response resp) {
    final header = resp.headers['retry-after'];
    if (header != null) {
      final secs = int.tryParse(header.trim());
      if (secs != null) return Duration(seconds: secs);
    }
    final match = RegExp(r'retryDelay"?\s*:\s*"?([0-9.]+)s', caseSensitive: false)
            .firstMatch(resp.body) ??
        RegExp(r'retry in ([0-9.]+)s', caseSensitive: false)
            .firstMatch(resp.body);
    if (match != null) {
      final secs = double.tryParse(match.group(1)!);
      if (secs != null) {
        return Duration(milliseconds: (secs * 1000).round());
      }
    }
    return null;
  }

  /// 출력 토큰 상한: 오디오 길이에 대략 비례(폭주 비용 차단, 정상 자막은 안 잘림).
  /// 16kHz mono 16-bit ≈ 32000 bytes/sec. 초당 ~60토큰 + 여유.
  static int _maxOutputTokensFor(int audioByteLength) {
    final seconds = audioByteLength / 32000.0;
    return (seconds * 60).round() + 256;
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

/// 캡션 응답 스키마: `{ sourceLanguage, segments:[{start,end,source,text}] }`.
const Map<String, dynamic> _captionSchema = <String, dynamic>{
  'type': 'OBJECT',
  'properties': <String, dynamic>{
    'sourceLanguage': <String, String>{'type': 'STRING'},
    'segments': <String, dynamic>{
      'type': 'ARRAY',
      'items': <String, dynamic>{
        'type': 'OBJECT',
        'properties': <String, dynamic>{
          'start': <String, String>{'type': 'NUMBER'},
          'end': <String, String>{'type': 'NUMBER'},
          'source': <String, String>{'type': 'STRING'},
          'text': <String, String>{'type': 'STRING'},
        },
        'required': <String>['start', 'end', 'source', 'text'],
      },
    },
  },
  'required': <String>['segments'],
};

/// 캡션용 시스템 지시문(순수 함수, 테스트 대상).
String buildGeminiCaptionInstruction({
  required String target,
  String? languageHint,
}) {
  final targetName = languageDisplayName(target);
  final maxChars = AppConfig.maxSegmentChars;
  final maxSec = AppConfig.maxSegmentDuration.inSeconds;
  final lines = <String>[
    'You are a video subtitle engine. Transcribe the speech in the provided '
        'audio clip, then translate each segment into $targetName.',
    '- Split into natural sentence/clause segments. Each segment must be at most '
        'about $maxSec seconds long and about $maxChars characters.',
    '- "start" and "end" are the segment time bounds in SECONDS (decimal), '
        'relative to the START of THIS audio clip (the clip begins at 0).',
    '- "source" = the original transcribed text. "text" = its natural, '
        'colloquial $targetName subtitle translation as a native speaker would '
        'actually say it (NOT a literal word-for-word translation).',
  ];
  if (target == 'ko') {
    lines.add(
        '- For Korean, use a natural, polite conversational register (해요체).');
  }
  if (languageHint != null && languageHint.trim().isNotEmpty) {
    lines.add(
        '- The spoken language is likely ${languageDisplayName(languageHint)}.');
  }
  lines.addAll(<String>[
    '- If a segment is already in $targetName, copy it unchanged into "text".',
    '- Report the detected spoken language as a BCP-47/ISO code in '
        '"sourceLanguage".',
    '- If there is no intelligible speech, return an empty "segments" array.',
    '- Output ONLY the JSON object — no commentary, no code fences.',
  ]);
  return lines.join('\n');
}

/// Gemini 캡션 응답을 자막 큐로 파싱(순수 함수, 테스트 대상).
///
/// 타임스탬프는 윈도우 기준 상대값(초)이며 호출자가 윈도우 시작만큼 민다. 무음/세그먼트 없음은
/// 빈 리스트로(예외 아님), JSON 자체가 깨졌을 때만 [CaptionException]을 던진다.
List<SubtitleCue> parseGeminiCaptionResponse(String responseBody) {
  final Map<String, dynamic> json;
  try {
    json = jsonDecode(responseBody) as Map<String, dynamic>;
  } catch (e) {
    throw CaptionException('Gemini 응답 JSON 파싱 실패: $e');
  }

  final candidates = json['candidates'];
  if (candidates is! List || candidates.isEmpty) {
    throw CaptionException('Gemini 응답에 후보가 없음');
  }
  final content = (candidates.first as Map)['content'];
  final parts = content is Map ? content['parts'] : null;
  // parts 없음(안전 차단 등) → 무음 취급.
  if (parts is! List || parts.isEmpty) return <SubtitleCue>[];

  final buffer = StringBuffer();
  for (final p in parts) {
    if (p is Map && p['text'] is String) buffer.write(p['text'] as String);
  }
  final payload = _stripJsonFence(buffer.toString().trim());
  if (payload.isEmpty) return <SubtitleCue>[];

  final Object? decoded;
  try {
    decoded = jsonDecode(payload);
  } catch (e) {
    throw CaptionException('Gemini 캡션 파싱 실패: $e');
  }
  if (decoded is! Map) return <SubtitleCue>[];

  final lang = decoded['sourceLanguage'];
  final langCode =
      lang is String && lang.trim().isNotEmpty ? lang.trim() : null;
  final segs = decoded['segments'];
  if (segs is! List) return <SubtitleCue>[];

  final cues = <SubtitleCue>[];
  for (final s in segs) {
    if (s is! Map) continue;
    final translated = (s['text'] as Object?)?.toString().trim() ?? '';
    final source = (s['source'] as Object?)?.toString().trim() ?? '';
    final display = translated.isNotEmpty ? translated : source;
    if (display.isEmpty) continue;
    final start = _secondsToDuration(s['start']);
    var end = _secondsToDuration(s['end']);
    if (end < start) end = start;
    cues.add(SubtitleCue(
      start: start,
      end: end,
      text: display,
      sourceText: source.isEmpty ? null : source,
      languageCode: langCode,
    ));
  }
  return cues;
}

/// 초(숫자/문자열) → [Duration]. 음수·비정상은 0으로 클램프.
Duration _secondsToDuration(Object? raw) {
  double seconds;
  if (raw is num) {
    seconds = raw.toDouble();
  } else {
    seconds = double.tryParse(raw?.toString().trim() ?? '') ?? 0;
  }
  if (seconds.isNaN || seconds.isInfinite || seconds < 0) seconds = 0;
  return Duration(
      microseconds: (seconds * Duration.microsecondsPerSecond).round());
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
