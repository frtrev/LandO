import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lando/models/chat_message.dart';
import 'package:lando/services/assistant/gemini_assistant.dart';
import 'package:lando/services/assistant/lando_assistant.dart';
import 'support/assistant_fixtures.dart';

http.Response geminiResponse(
  List<Map<String, dynamic>> parts, {
  String finish = 'STOP',
}) => http.Response(
  jsonEncode({
    'candidates': [
      {
        'finishReason': finish,
        'content': {'role': 'model', 'parts': parts},
      },
    ],
  }),
  200,
);
void main() {
  test(
    'Gemini replays thought signatures and function IDs, computes locally and keeps its key out of URLs',
    () async {
      var round = 0;
      final assistant = GeminiAssistant(
        client: MockClient((request) async {
          expect(
            request.url.toString(),
            'https://generativelanguage.googleapis.com/v1beta/models/gemini-test:generateContent',
          );
          expect(request.url.query, isEmpty);
          expect(request.headers['x-goog-api-key'], 'google-private-test');
          expect(request.headers.containsKey('Authorization'), false);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(jsonEncode(body), isNot(contains('google-private-test')));
          final declaration = body['tools'][0]['functionDeclarations'][0];
          expect(declaration['name'], 'get_property_summary');
          expect(declaration['parametersJsonSchema']['type'], 'object');
          final contents = body['contents'] as List;
          expect(contents[0]['role'], 'user');
          expect(contents[1]['role'], 'model');
          round++;
          if (round == 1) {
            expect(
              body['toolConfig']['functionCallingConfig']['allowedFunctionNames'],
              ['get_property_summary'],
            );
            return geminiResponse([
              {
                'functionCall': {
                  'name': 'get_property_summary',
                  'id': 'summary',
                  'args': {},
                },
                'thoughtSignature': 'opaque-summary',
              },
            ]);
          }
          expect(body['toolConfig']['functionCallingConfig']['mode'], 'AUTO');
          expect(contents[3]['parts'][0]['thoughtSignature'], 'opaque-summary');
          expect(contents[4]['parts'][0]['functionResponse']['id'], 'summary');
          expect(
            contents[4]['parts'][0]['functionResponse']['response']['property_name'],
            'My pasture',
          );
          if (round == 2) {
            return geminiResponse([
              {
                'functionCall': {
                  'name': 'get_property_perimeter',
                  'id': 'perimeter',
                  'args': {},
                },
                'thoughtSignature': 'opaque-perimeter',
              },
            ]);
          }
          expect(
            contents[5]['parts'][0]['thoughtSignature'],
            'opaque-perimeter',
          );
          expect(
            contents[6]['parts'][0]['functionResponse']['response']['perimeter_m'],
            greaterThan(0),
          );
          return geminiResponse([
            {'text': 'Private model reasoning', 'thought': true},
            {'text': 'Your boundary is a planning estimate.'},
          ]);
        }),
      );
      final result = await assistant.ask(
        property: exampleProperty(),
        history: [
          ChatMessage(role: 'user', text: 'Hi'),
          ChatMessage(role: 'assistant', text: 'Hello'),
          ChatMessage(role: 'user', text: 'Boundary?'),
        ],
        apiKey: 'google-private-test',
        model: 'gemini-test',
      );
      expect(round, 3);
      expect(result.calculations, hasLength(2));
      expect(result.text, 'Your boundary is a planning estimate.');
      assistant.dispose();
    },
  );
  test(
    'all parallel Gemini tool calls get separate responses; malformed arguments are recoverable',
    () async {
      var round = 0;
      final assistant = GeminiAssistant(
        client: MockClient((request) async {
          round++;
          if (round == 1) {
            return geminiResponse([
              {
                'functionCall': {'name': 'get_property_summary', 'args': {}},
              },
            ]);
          }
          if (round == 2) {
            return geminiResponse([
              {
                'functionCall': {
                  'name': 'get_property_area',
                  'id': 'good',
                  'args': {},
                },
              },
              {
                'functionCall': {
                  'name': 'calculate_gravel_volume',
                  'id': 'bad',
                  'args': 'invalid',
                },
              },
            ]);
          }
          final contents = jsonDecode(request.body)['contents'] as List;
          final results = contents.last['parts'] as List;
          expect(results, hasLength(2));
          expect(results[0]['functionResponse']['id'], 'good');
          expect(results[1]['functionResponse']['response']['status'], 'error');
          return geminiResponse([
            {'text': 'What width and depth should I use?'},
          ]);
        }),
      );
      final result = await assistant.ask(
        property: exampleProperty(),
        history: [ChatMessage(role: 'user', text: 'Gravel?')],
        apiKey: 'google-test',
        model: 'gemini-test',
      );
      expect(result.calculations, hasLength(3));
      assistant.dispose();
    },
  );
  test(
    'Gemini errors, blocked prompts and truncation do not expose keys or trusted partial answers',
    () async {
      for (final status in [400, 401, 403, 404, 429, 503]) {
        final assistant = GeminiAssistant(
          client: MockClient(
            (_) async => http.Response('google-secret', status),
          ),
        );
        await expectLater(
          assistant.ask(
            property: exampleProperty(),
            history: [],
            apiKey: 'google-secret',
            model: 'gemini-test',
          ),
          throwsA(
            isA<AssistantException>().having(
              (e) => e.message,
              'safe error',
              isNot(contains('google-secret')),
            ),
          ),
        );
        assistant.dispose();
      }
      for (final response in [
        geminiResponse([
          {'text': 'Partial incorrect total'},
        ], finish: 'MAX_TOKENS'),
        http.Response('{"promptFeedback":{"blockReason":"SAFETY"}}', 200),
      ]) {
        final assistant = GeminiAssistant(
          client: MockClient((_) async => response),
        );
        await expectLater(
          assistant.ask(
            property: exampleProperty(),
            history: [],
            apiKey: 'google-test',
            model: 'gemini-test',
          ),
          throwsA(isA<AssistantException>()),
        );
        assistant.dispose();
      }
    },
  );
  test(
    'Gemini stops a runaway tool loop and validates model IDs before making requests',
    () async {
      var count = 0;
      final assistant = GeminiAssistant(
        client: MockClient((_) async {
          count++;
          return geminiResponse([
            {
              'functionCall': {'name': 'get_property_summary', 'args': {}},
            },
          ]);
        }),
      );
      await expectLater(
        assistant.ask(
          property: exampleProperty(),
          history: [],
          apiKey: 'key',
          model: 'gemini-test',
        ),
        throwsA(isA<AssistantException>()),
      );
      expect(count, 8);
      await expectLater(
        assistant.ask(
          property: exampleProperty(),
          history: [],
          apiKey: 'key',
          model: '../../bad?key=secret',
        ),
        throwsA(isA<AssistantException>()),
      );
      expect(count, 8);
      assistant.dispose();
    },
  );
}
