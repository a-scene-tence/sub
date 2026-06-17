import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:video_subtitle_translator/services/speech_service.dart';

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
