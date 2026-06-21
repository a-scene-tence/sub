import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_subtitle_translator/services/gemini_caption_service.dart';

/// candidates[0].content.parts[0].text 형태로 감싼 Gemini 응답 본문을 만든다.
String wrap(String payloadText) => jsonEncode(<String, dynamic>{
      'candidates': <dynamic>[
        <String, dynamic>{
          'content': <String, dynamic>{
            'parts': <dynamic>[
              <String, dynamic>{'text': payloadText},
            ],
          },
        },
      ],
    });

void main() {
  group('parseGeminiCaptionResponse', () {
    test('정상 다중 세그먼트: 초→Duration, 원문/번역 보존', () {
      final body = wrap(jsonEncode(<String, dynamic>{
        'sourceLanguage': 'en-US',
        'segments': <dynamic>[
          {'start': 0.5, 'end': 1.5, 'source': 'Hello', 'text': '안녕하세요'},
          {'start': 2, 'end': 3.25, 'source': 'Bye', 'text': '안녕히 가세요'},
        ],
      }));

      final cues = parseGeminiCaptionResponse(body);

      expect(cues.length, 2);
      expect(cues[0].start, const Duration(milliseconds: 500));
      expect(cues[0].end, const Duration(milliseconds: 1500));
      expect(cues[0].text, '안녕하세요');
      expect(cues[0].sourceText, 'Hello');
      expect(cues[0].languageCode, 'en-US');
      expect(cues[1].start, const Duration(seconds: 2));
      expect(cues[1].end, const Duration(milliseconds: 3250));
    });

    test('end < start면 start로 클램프', () {
      final body = wrap(jsonEncode(<String, dynamic>{
        'segments': <dynamic>[
          {'start': 5, 'end': 2, 'source': 'x', 'text': 'y'},
        ],
      }));
      final cues = parseGeminiCaptionResponse(body);
      expect(cues.single.start, const Duration(seconds: 5));
      expect(cues.single.end, const Duration(seconds: 5));
    });

    test('빈 segments는 빈 리스트(무음)', () {
      final body = wrap(jsonEncode(<String, dynamic>{'segments': <dynamic>[]}));
      expect(parseGeminiCaptionResponse(body), isEmpty);
    });

    test('text 비고 source만 있으면 source를 표시문으로 사용', () {
      final body = wrap(jsonEncode(<String, dynamic>{
        'segments': <dynamic>[
          {'start': 0, 'end': 1, 'source': '그대로', 'text': ''},
        ],
      }));
      final cues = parseGeminiCaptionResponse(body);
      expect(cues.single.text, '그대로');
    });

    test('표시할 내용이 전혀 없는 세그먼트는 건너뜀', () {
      final body = wrap(jsonEncode(<String, dynamic>{
        'segments': <dynamic>[
          {'start': 0, 'end': 1, 'source': '', 'text': ''},
          {'start': 1, 'end': 2, 'source': 'ok', 'text': '좋아요'},
        ],
      }));
      final cues = parseGeminiCaptionResponse(body);
      expect(cues.length, 1);
      expect(cues.single.text, '좋아요');
    });

    test('```json 펜스로 감싼 페이로드도 파싱', () {
      final inner = jsonEncode(<String, dynamic>{
        'segments': <dynamic>[
          {'start': 0, 'end': 1, 'source': 'hi', 'text': '안녕'},
        ],
      });
      final cues = parseGeminiCaptionResponse(wrap('```json\n$inner\n```'));
      expect(cues.single.text, '안녕');
    });

    test('parts 없음(안전 차단 등)은 빈 리스트', () {
      final body = jsonEncode(<String, dynamic>{
        'candidates': <dynamic>[
          <String, dynamic>{'content': <String, dynamic>{}},
        ],
      });
      expect(parseGeminiCaptionResponse(body), isEmpty);
    });

    test('후보 없음은 예외', () {
      final body = jsonEncode(<String, dynamic>{'candidates': <dynamic>[]});
      expect(() => parseGeminiCaptionResponse(body),
          throwsA(isA<CaptionException>()));
    });

    test('깨진 JSON은 예외', () {
      expect(() => parseGeminiCaptionResponse('not json'),
          throwsA(isA<CaptionException>()));
    });
  });

  group('buildGeminiCaptionInstruction', () {
    test('대상 언어명 포함', () {
      final ins = buildGeminiCaptionInstruction(target: 'en');
      expect(ins, contains('English'));
    });

    test('한국어 대상은 해요체 지시 포함', () {
      final ins = buildGeminiCaptionInstruction(target: 'ko');
      expect(ins, contains('해요체'));
    });

    test('언어 힌트가 있으면 소스 언어 안내 포함', () {
      final ins =
          buildGeminiCaptionInstruction(target: 'ko', languageHint: 'ja');
      expect(ins, contains('日本語'));
    });
  });
}
