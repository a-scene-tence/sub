import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/recognition_result.dart';
import '../models/transcript_segment.dart';

/// STT 호출 실패를 나타내는 예외(메시지에 API 키를 포함하지 않는다).
class SpeechException implements Exception {
  SpeechException(this.message);
  final String message;
  @override
  String toString() => 'SpeechException: $message';
}

/// 음성 인식 + 언어 감지 추상 인터페이스.
///
/// MVP 구현은 인라인(base64) 동기 인식(≤60초). 장편(GCS+longRunning)은
/// 동일 인터페이스로 Phase 2에 추가할 수 있다.
abstract class SpeechService {
  /// [audioBytes](16kHz mono LINEAR16 WAV/PCM)를 인식해 단어 타임스탬프 기반
  /// 자막 세그먼트와 감지 언어를 반환.
  Future<RecognitionResult> recognize(
    List<int> audioBytes, {
    String? languageHint,
  });
}

/// Google Cloud Speech-to-Text v1 (동기 `speech:recognize`) 구현.
class GoogleSpeechService implements SpeechService {
  GoogleSpeechService({
    required this.apiKey,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  @override
  Future<RecognitionResult> recognize(
    List<int> audioBytes, {
    String? languageHint,
  }) async {
    final candidates = List<String>.from(AppConfig.languageCandidates);
    final primary = languageHint ?? candidates.first;
    // 기본 언어를 제외한 나머지를 자동 감지 후보로.
    final alternatives = candidates.where((c) => c != primary).toList();

    final body = <String, dynamic>{
      'config': <String, dynamic>{
        'encoding': AppConfig.sttEncoding,
        'sampleRateHertz': AppConfig.sampleRateHertz,
        'audioChannelCount': AppConfig.audioChannels,
        'languageCode': primary,
        'alternativeLanguageCodes': alternatives,
        'enableWordTimeOffsets': true,
        'enableAutomaticPunctuation': true,
      },
      'audio': <String, dynamic>{
        'content': base64Encode(audioBytes),
      },
    };

    final uri = Uri.parse('${AppConfig.sttRecognizeUrl}?key=$apiKey');
    final http.Response resp;
    try {
      resp = await _client.post(
        uri,
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
    } catch (e) {
      throw SpeechException('네트워크 오류: $e');
    }

    if (resp.statusCode != 200) {
      throw SpeechException(
          'STT 실패 (HTTP ${resp.statusCode}): ${_errorMessage(resp.body)}');
    }

    return parseRecognizeResponse(resp.body);
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

/// `speech:recognize` 응답 JSON을 [RecognitionResult]로 파싱한다(순수 함수, 테스트 대상).
///
/// 단어 타임오프셋(`words`)이 있으면 단어 단위로, 없으면 전체 transcript를
/// 하나의 세그먼트(시간 0~0)로 만든다. 빈 결과는 [RecognitionResult.empty].
RecognitionResult parseRecognizeResponse(String responseBody) {
  final Map<String, dynamic> json;
  try {
    json = jsonDecode(responseBody) as Map<String, dynamic>;
  } catch (e) {
    throw SpeechException('STT 응답 JSON 파싱 실패: $e');
  }

  final results = json['results'];
  if (results is! List || results.isEmpty) return RecognitionResult.empty;

  final words = <TranscriptWord>[];
  final fallbackTranscripts = <String>[];
  String detected = '';
  final langCounts = <String, int>{};

  for (final result in results) {
    if (result is! Map) continue;
    final lang = (result['languageCode'] as String?)?.trim();
    final alternatives = result['alternatives'];
    if (alternatives is! List || alternatives.isEmpty) continue;
    final best = alternatives.first;
    if (best is! Map) continue;

    final transcript = (best['transcript'] as String?)?.trim() ?? '';
    if (transcript.isNotEmpty) fallbackTranscripts.add(transcript);

    final wordList = best['words'];
    if (wordList is List) {
      for (final w in wordList) {
        if (w is! Map) continue;
        final text = (w['word'] as String?)?.trim() ?? '';
        if (text.isEmpty) continue;
        words.add(TranscriptWord(
          start: parseSttDuration(w['startTime']),
          end: parseSttDuration(w['endTime']),
          word: text,
        ));
        if (lang != null && lang.isNotEmpty) {
          langCounts[lang] = (langCounts[lang] ?? 0) + 1;
        }
      }
    } else if (lang != null && lang.isNotEmpty) {
      langCounts[lang] = (langCounts[lang] ?? 0) + 1;
    }
  }

  if (langCounts.isNotEmpty) {
    detected =
        langCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  // 단어 타임스탬프가 있으면 CueBuilder가 세그먼트화하도록 단어를 세그먼트로 감싼다.
  if (words.isNotEmpty) {
    final segments = words
        .map((w) => TranscriptSegment(
              start: w.start,
              end: w.end,
              text: w.word,
              languageCode: detected.isEmpty ? 'und' : detected,
            ))
        .toList();
    return RecognitionResult(
        segments: segments, detectedLanguageCode: detected);
  }

  // 타임스탬프가 없으면 전체 transcript 하나로.
  if (fallbackTranscripts.isNotEmpty) {
    return RecognitionResult(
      segments: <TranscriptSegment>[
        TranscriptSegment(
          start: Duration.zero,
          end: Duration.zero,
          text: fallbackTranscripts.join(' '),
          languageCode: detected.isEmpty ? 'und' : detected,
        ),
      ],
      detectedLanguageCode: detected,
    );
  }

  return RecognitionResult.empty;
}
