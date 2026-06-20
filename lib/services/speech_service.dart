import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/recognition_result.dart';
import '../models/transcript_segment.dart';
import 'wav_chunker.dart';

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
        'sampleRateHertz': wavSampleRate(audioBytes) ?? AppConfig.sampleRateHertz,
        'audioChannelCount': wavChannels(audioBytes) ?? AppConfig.audioChannels,
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

/// 긴 영상 지원: 동기 `recognize`(≤60초/10MB)를 우회하기 위해 WAV를 고정 길이 청크로
/// 잘라 [base]로 청크별 인식한 뒤, 타임스탬프를 청크 오프셋만큼 밀어 하나로 병합한다.
///
/// API 키 인증을 그대로 유지하며(GCS/longRunning 불필요), 짧은 클립은 1청크로 [base]에
/// 그대로 위임한다. 청크는 순차 호출이라 영상이 길수록 처리 시간·비용이 비례해 늘어난다
/// (추후 병렬화 여지). 청크 경계에서 단어 하나가 잘릴 수 있으나 자막 용도에선 허용 수준.
class ChunkedSpeechRecognizer implements SpeechService {
  ChunkedSpeechRecognizer(this.base, {Duration? chunkDuration})
      : chunkDuration = chunkDuration ?? AppConfig.sttChunkDuration;

  final SpeechService base;
  final Duration chunkDuration;

  @override
  Future<RecognitionResult> recognize(
    List<int> audioBytes, {
    String? languageHint,
  }) async {
    final chunks = splitWav(audioBytes, chunk: chunkDuration);
    if (chunks.length <= 1) {
      return base.recognize(audioBytes, languageHint: languageHint);
    }

    final merged = <TranscriptSegment>[];
    final langCounts = <String, int>{};
    for (final chunk in chunks) {
      final r = await base.recognize(chunk.bytes, languageHint: languageHint);
      for (final s in r.segments) {
        merged.add(s.copyWith(
          start: s.start + chunk.offset,
          end: s.end + chunk.offset,
        ));
      }
      final lang = r.detectedLanguageCode;
      if (lang.isNotEmpty) {
        langCounts[lang] = (langCounts[lang] ?? 0) + r.segments.length;
      }
    }

    if (merged.isEmpty) return RecognitionResult.empty;
    final detected = langCounts.isEmpty
        ? ''
        : langCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    return RecognitionResult(segments: merged, detectedLanguageCode: detected);
  }
}

/// WAV(RIFF) 헤더에서 샘플레이트를 읽는다. WAV가 아니거나 헤더가 짧으면 `null`.
///
/// 네이티브 추출기가 소스 네이티브 레이트로 WAV를 만들므로, STT 요청 레이트는 이 값을 따른다.
/// 오프셋: 0–3 `RIFF`, 8–11 `WAVE`, 24–27 샘플레이트(little-endian).
int? wavSampleRate(List<int> bytes) {
  if (!_isWav(bytes)) return null;
  return _readU32le(bytes, 24);
}

/// WAV(RIFF) 헤더에서 채널 수를 읽는다(오프셋 22–23, little-endian). 아니면 `null`.
int? wavChannels(List<int> bytes) {
  if (!_isWav(bytes)) return null;
  return bytes[22] | (bytes[23] << 8);
}

bool _isWav(List<int> b) {
  if (b.length < 44) return false;
  // 'RIFF' .... 'WAVE'
  return b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x41 &&
      b[10] == 0x56 &&
      b[11] == 0x45;
}

int _readU32le(List<int> b, int o) =>
    b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

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
