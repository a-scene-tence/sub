import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:video_subtitle_translator/models/recognition_result.dart';
import 'package:video_subtitle_translator/models/transcript_segment.dart';
import 'package:video_subtitle_translator/services/speech_service.dart';
import 'package:video_subtitle_translator/services/wav_chunker.dart'
    show buildWavHeader;

void main() {
  group('parseRecognizeResponse', () {
    test('빈 results는 empty', () {
      final r = parseRecognizeResponse(jsonEncode(<String, dynamic>{}));
      expect(r.isEmpty, isTrue);
      final r2 = parseRecognizeResponse(
          jsonEncode(<String, dynamic>{'results': <dynamic>[]}));
      expect(r2.isEmpty, isTrue);
    });

    test('단어 타임오프셋 파싱 + 언어 감지', () {
      final body = jsonEncode(<String, dynamic>{
        'results': <dynamic>[
          <String, dynamic>{
            'languageCode': 'en-us',
            'alternatives': <dynamic>[
              <String, dynamic>{
                'transcript': 'hello world',
                'words': <dynamic>[
                  <String, dynamic>{
                    'word': 'hello',
                    'startTime': '0s',
                    'endTime': '0.500s',
                  },
                  <String, dynamic>{
                    'word': 'world',
                    'startTime': '0.500s',
                    'endTime': '1.200s',
                  },
                ],
              },
            ],
          },
        ],
      });
      final r = parseRecognizeResponse(body);
      expect(r.segments.length, 2);
      expect(r.segments[0].text, 'hello');
      expect(r.segments[0].end, const Duration(milliseconds: 500));
      expect(r.segments[1].end, const Duration(milliseconds: 1200));
      expect(r.detectedLanguageCode, 'en-us');
    });

    test('단어 오프셋 없으면 transcript 하나로 fallback (0~0)', () {
      final body = jsonEncode(<String, dynamic>{
        'results': <dynamic>[
          <String, dynamic>{
            'languageCode': 'ko-kr',
            'alternatives': <dynamic>[
              <String, dynamic>{'transcript': '안녕하세요'},
            ],
          },
        ],
      });
      final r = parseRecognizeResponse(body);
      expect(r.segments.length, 1);
      expect(r.segments[0].text, '안녕하세요');
      expect(r.segments[0].start, Duration.zero);
      expect(r.segments[0].end, Duration.zero);
    });

    test('잘못된 JSON은 SpeechException', () {
      expect(() => parseRecognizeResponse('not json'),
          throwsA(isA<SpeechException>()));
    });
  });

  group('wavSampleRate / wavChannels', () {
    test('유효한 WAV 헤더에서 레이트·채널 파싱', () {
      final wav = _wavBytes(sampleRate: 44100, channels: 2);
      expect(wavSampleRate(wav), 44100);
      expect(wavChannels(wav), 2);
    });

    test('WAV가 아니거나 너무 짧으면 null', () {
      expect(wavSampleRate(<int>[1, 2, 3]), isNull);
      expect(wavChannels(<int>[1, 2, 3]), isNull);
      final notRiff = List<int>.filled(44, 0);
      expect(wavSampleRate(notRiff), isNull);
    });
  });

  group('ChunkedSpeechRecognizer.recognizeFile', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('rec_test');
    });
    tearDown(() async {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    Future<File> writeWav(int dataBytes) async {
      final wav = <int>[
        ...buildWavHeader(sampleRate: 16000, channels: 1, dataLength: dataBytes),
        ...List<int>.filled(dataBytes, 0),
      ];
      final f = File('${tmp.path}/a.wav');
      await f.writeAsBytes(wav);
      return f;
    }

    test('다청크: 청크별 호출 + 오프셋 병합 + 진행 콜백', () async {
      // 16kHz mono 16-bit = 32000 B/s. 3초 = 96000B. 1초 청크 → 3조각.
      final file = await writeWav(96000);
      final base = _FakeBase();
      final rec = ChunkedSpeechRecognizer(base,
          chunkDuration: const Duration(seconds: 1));
      final progress = <int>[];

      final result = await rec.recognizeFile(
        file,
        languageHint: 'en-US',
        onProgress: (done, total) {
          expect(total, 3);
          progress.add(done);
        },
      );

      expect(base.calls, 3);
      // 각 청크는 헤더(44) + 32000B PCM = 32044B로 전달된다(메모리 스트리밍).
      expect(base.receivedLengths, everyElement(44 + 32000));
      expect(result.segments.length, 3);
      expect(result.segments[0].start, const Duration(milliseconds: 500));
      expect(result.segments[1].start, const Duration(milliseconds: 1500));
      expect(result.segments[2].start, const Duration(milliseconds: 2500));
      expect(result.detectedLanguageCode, 'en-US');
      expect(progress, <int>[1, 2, 3]);
    });

    test('단일 청크(짧은 입력)는 base에 통째로 위임', () async {
      final file = await writeWav(1000);
      final base = _FakeBase();
      final rec = ChunkedSpeechRecognizer(base,
          chunkDuration: const Duration(seconds: 50));

      final result = await rec.recognizeFile(file);

      expect(base.calls, 1);
      expect(base.receivedLengths.single, 44 + 1000); // 분할 없이 전체 파일
      expect(result.segments.single.start, const Duration(milliseconds: 500));
    });
  });

  group('GoogleSpeechService.recognize', () {
    test('요청 URL과 바디 구성 확인 + 결과 파싱', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'results': <dynamic>[
              <String, dynamic>{
                'languageCode': 'en-us',
                'alternatives': <dynamic>[
                  <String, dynamic>{
                    'transcript': 'hi',
                    'words': <dynamic>[
                      <String, dynamic>{
                        'word': 'hi',
                        'startTime': '0s',
                        'endTime': '0.300s',
                      },
                    ],
                  },
                ],
              },
            ],
          }),
          200,
        );
      });

      final service = GoogleSpeechService(apiKey: 'KEY123', client: client);
      final result =
          await service.recognize(<int>[1, 2, 3], languageHint: 'en-US');

      expect(captured.url.queryParameters['key'], 'KEY123');
      final sentBody = jsonDecode(captured.body) as Map<String, dynamic>;
      final config = sentBody['config'] as Map<String, dynamic>;
      expect(config['encoding'], 'LINEAR16');
      expect(config['sampleRateHertz'], 16000);
      expect(config['languageCode'], 'en-US');
      expect(config['enableWordTimeOffsets'], true);
      expect(
          (sentBody['audio'] as Map)['content'], base64Encode(<int>[1, 2, 3]));
      expect(result.segments.single.text, 'hi');
    });

    test('WAV 헤더의 실제 샘플레이트/채널을 요청에 사용', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(jsonEncode(<String, dynamic>{}), 200);
      });
      final wav = _wavBytes(sampleRate: 48000, channels: 1);

      final service = GoogleSpeechService(apiKey: 'K', client: client);
      await service.recognize(wav, languageHint: 'en-US');

      final config =
          (jsonDecode(captured.body) as Map<String, dynamic>)['config']
              as Map<String, dynamic>;
      expect(config['sampleRateHertz'], 48000);
      expect(config['audioChannelCount'], 1);
    });

    test('HTTP 오류는 SpeechException(메시지에 키 미포함)', () async {
      final client = MockClient((req) async {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'error': <String, dynamic>{'message': 'INVALID_ARGUMENT'},
          }),
          400,
        );
      });
      final service = GoogleSpeechService(apiKey: 'SECRET', client: client);
      await expectLater(
        service.recognize(<int>[1]),
        throwsA(
          isA<SpeechException>().having(
            (e) => e.message,
            'message',
            allOf(contains('INVALID_ARGUMENT'), isNot(contains('SECRET'))),
          ),
        ),
      );
    });
  });
}

/// 청크마다 0.5s~1.0s 세그먼트 하나를 돌려주는 가짜 STT. 호출 인자를 기록한다.
class _FakeBase implements SpeechService {
  int calls = 0;
  final List<int> receivedLengths = <int>[];

  @override
  Future<RecognitionResult> recognize(
    List<int> audioBytes, {
    String? languageHint,
  }) async {
    receivedLengths.add(audioBytes.length);
    final i = calls++;
    return RecognitionResult(
      segments: <TranscriptSegment>[
        TranscriptSegment(
          start: const Duration(milliseconds: 500),
          end: const Duration(seconds: 1),
          text: 'seg$i',
          languageCode: 'en-US',
        ),
      ],
      detectedLanguageCode: 'en-US',
    );
  }
}

/// 테스트용 최소 PCM WAV 헤더(44바이트) + 16바이트 더미 데이터 생성.
List<int> _wavBytes({required int sampleRate, required int channels}) {
  const bitsPerSample = 16;
  const dataSize = 16;
  final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
  final blockAlign = channels * bitsPerSample ~/ 8;
  final b = BytesBuilder();
  void ascii(String s) => b.add(s.codeUnits);
  void u32(int v) => b.add(<int>[
        v & 0xFF,
        (v >> 8) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 24) & 0xFF,
      ]);
  void u16(int v) => b.add(<int>[v & 0xFF, (v >> 8) & 0xFF]);

  ascii('RIFF');
  u32(36 + dataSize);
  ascii('WAVE');
  ascii('fmt ');
  u32(16);
  u16(1);
  u16(channels);
  u32(sampleRate);
  u32(byteRate);
  u16(blockAlign);
  u16(bitsPerSample);
  ascii('data');
  u32(dataSize);
  b.add(List<int>.filled(dataSize, 0));
  return b.toBytes();
}
