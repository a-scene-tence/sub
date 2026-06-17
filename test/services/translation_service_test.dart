import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:video_subtitle_translator/services/translation_service.dart';

void main() {
  group('parseTranslateResponse', () {
    test('번역문 추출 + HTML 엔티티 디코드', () {
      final body = jsonEncode(<String, dynamic>{
        'data': <String, dynamic>{
          'translations': <dynamic>[
            <String, dynamic>{'translatedText': 'It&#39;s ok'},
            <String, dynamic>{'translatedText': 'A &amp; B'},
          ],
        },
      });
      final out = parseTranslateResponse(body, expected: 2);
      expect(out, <String>["It's ok", 'A & B']);
    });

    test('개수 불일치는 예외', () {
      final body = jsonEncode(<String, dynamic>{
        'data': <String, dynamic>{
          'translations': <dynamic>[
            <String, dynamic>{'translatedText': 'x'},
          ],
        },
      });
      expect(() => parseTranslateResponse(body, expected: 2),
          throwsA(isA<TranslationException>()));
    });

    test('형식 오류는 예외', () {
      expect(() => parseTranslateResponse('{}', expected: 1),
          throwsA(isA<TranslationException>()));
    });
  });

  group('GoogleTranslationService.translateBatch', () {
    test('빈 입력은 호출 없이 빈 결과', () async {
      var called = false;
      final client = MockClient((req) async {
        called = true;
        return http.Response('{}', 200);
      });
      final service = GoogleTranslationService(apiKey: 'K', client: client);
      expect(await service.translateBatch(<String>[], target: 'ko'), isEmpty);
      expect(called, isFalse);
    });

    test('source == target 이면 네트워크 호출 없이 원문 반환', () async {
      var called = false;
      final client = MockClient((req) async {
        called = true;
        return http.Response('{}', 200);
      });
      final service = GoogleTranslationService(apiKey: 'K', client: client);
      final out = await service
          .translateBatch(<String>['hi'], target: 'en', source: 'en-US');
      expect(out, <String>['hi']);
      expect(called, isFalse);
    });

    test('요청 바디(BCP-47 -> ISO 매핑)와 결과 파싱', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'data': <String, dynamic>{
              'translations': <dynamic>[
                <String, dynamic>{'translatedText': '안녕'},
              ],
            },
          }),
          200,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });
      final service = GoogleTranslationService(apiKey: 'K', client: client);
      final out = await service
          .translateBatch(<String>['hi'], target: 'ko', source: 'en-US');

      final sent = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(sent['target'], 'ko');
      expect(sent['source'], 'en'); // en-US -> en
      expect(sent['q'], <String>['hi']);
      expect(out, <String>['안녕']);
    });

    test('HTTP 오류는 TranslationException', () async {
      final client = MockClient((req) async => http.Response(
            jsonEncode(<String, dynamic>{
              'error': <String, dynamic>{'message': 'quota'},
            }),
            403,
          ));
      final service = GoogleTranslationService(apiKey: 'K', client: client);
      await expectLater(
        service.translateBatch(<String>['hi'], target: 'ko'),
        throwsA(isA<TranslationException>()),
      );
    });
  });
}
