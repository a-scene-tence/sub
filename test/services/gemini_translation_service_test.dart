import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:video_subtitle_translator/services/gemini_translation_service.dart';
import 'package:video_subtitle_translator/services/translation_service.dart';

String _geminiBody(String text) => jsonEncode(<String, dynamic>{
      'candidates': <dynamic>[
        <String, dynamic>{
          'content': <String, dynamic>{
            'parts': <dynamic>[
              <String, dynamic>{'text': text},
            ],
          },
        },
      ],
    });

void main() {
  group('parseGeminiTranslateResponse', () {
    test('JSON 배열 후보를 리스트로 파싱', () {
      final body = _geminiBody(jsonEncode(<String>['안녕', '잘 가요']));
      expect(parseGeminiTranslateResponse(body, expected: 2),
          <String>['안녕', '잘 가요']);
    });

    test('```json 펜스로 감싸도 안쪽 JSON 파싱', () {
      final body = _geminiBody('```json\n["안녕"]\n```');
      expect(parseGeminiTranslateResponse(body, expected: 1), <String>['안녕']);
    });

    test('개수 불일치는 예외', () {
      final body = _geminiBody(jsonEncode(<String>['안녕']));
      expect(() => parseGeminiTranslateResponse(body, expected: 2),
          throwsA(isA<TranslationException>()));
    });

    test('후보 없음은 예외', () {
      expect(
          () => parseGeminiTranslateResponse(
              jsonEncode(<String, dynamic>{'candidates': <dynamic>[]}),
              expected: 1),
          throwsA(isA<TranslationException>()));
    });

    test('배열이 아닌 텍스트는 예외', () {
      final body = _geminiBody('그냥 문장');
      expect(() => parseGeminiTranslateResponse(body, expected: 1),
          throwsA(isA<TranslationException>()));
    });
  });

  group('buildGeminiInstruction', () {
    test('한국어 대상은 해요체 + 대상 언어명 포함', () {
      final inst = buildGeminiInstruction(target: 'ko', source: 'en');
      expect(inst, contains('해요체'));
      expect(inst, contains('한국어'));
      expect(inst, contains('English')); // 원문 언어 명시
    });

    test('비한국어 대상은 해요체 미포함', () {
      final inst = buildGeminiInstruction(target: 'ja');
      expect(inst, isNot(contains('해요체')));
      expect(inst, contains('日本語'));
    });
  });

  group('GeminiTranslationService.translateBatch', () {
    test('빈 입력은 호출 없이 빈 결과', () async {
      var called = false;
      final client = MockClient((req) async {
        called = true;
        return http.Response('{}', 200);
      });
      final service = GeminiTranslationService(apiKey: 'K', client: client);
      expect(await service.translateBatch(<String>[], target: 'ko'), isEmpty);
      expect(called, isFalse);
    });

    test('source == target 이면 호출 없이 원문 반환', () async {
      var called = false;
      final client = MockClient((req) async {
        called = true;
        return http.Response('{}', 200);
      });
      final service = GeminiTranslationService(apiKey: 'K', client: client);
      final out = await service
          .translateBatch(<String>['hi'], target: 'en', source: 'en-US');
      expect(out, <String>['hi']);
      expect(called, isFalse);
    });

    test('요청 형태(엔드포인트·스키마·원문 줄)와 결과 파싱', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(
          _geminiBody(jsonEncode(<String>['안녕', '오늘 어때요?'])),
          200,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });
      final service = GeminiTranslationService(apiKey: 'K', client: client);
      final out = await service.translateBatch(
        <String>['hi', 'how are you today?'],
        target: 'ko',
        source: 'en-US',
      );

      // 엔드포인트: 생성형 언어 API의 generateContent + 키.
      final url = captured.url.toString();
      expect(url, contains('generativelanguage.googleapis.com'));
      expect(url, contains(':generateContent'));
      expect(url, contains('key=K'));

      final sent = jsonDecode(captured.body) as Map<String, dynamic>;
      final gc = sent['generationConfig'] as Map<String, dynamic>;
      expect((gc['responseSchema'] as Map)['type'], 'ARRAY');
      expect(gc['responseMimeType'], 'application/json');
      // 비용 최소화: thinking 비활성 + 출력 상한이 요청에 포함된다.
      expect((gc['thinkingConfig'] as Map)['thinkingBudget'], 0);
      expect(gc['maxOutputTokens'], isA<int>());
      final userText = ((sent['contents'] as List).first as Map)['parts'][0]
          ['text'] as String;
      expect(userText, jsonEncode(<String>['hi', 'how are you today?']));

      expect(out, <String>['안녕', '오늘 어때요?']);
    });

    test('HTTP 오류는 TranslationException', () async {
      final client = MockClient((req) async => http.Response(
            jsonEncode(<String, dynamic>{
              'error': <String, dynamic>{'message': 'permission denied'},
            }),
            403,
          ));
      final service = GeminiTranslationService(apiKey: 'K', client: client);
      await expectLater(
        service.translateBatch(<String>['hi'], target: 'ko'),
        throwsA(isA<TranslationException>()),
      );
    });
  });
}
