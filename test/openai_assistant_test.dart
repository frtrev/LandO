import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lando/models/chat_message.dart';
import 'package:lando/services/assistant/openai_assistant.dart';
import 'support/assistant_fixtures.dart';

Map<String, dynamic> call(String name, String id, String arguments) => {
  'type': 'function_call',
  'id': 'fc_$id',
  'call_id': id,
  'name': name,
  'arguments': arguments,
};
http.Response response(
  List<Map<String, dynamic>> output, {
  String status = 'completed',
}) => http.Response(jsonEncode({'status': status, 'output': output}), 200);
void main() {
  test(
    'Responses loop replays reasoning and exact call IDs, computes locally, and disables response storage',
    () async {
      var round = 0;
      final assistant = OpenAiAssistant(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(request.url.toString(), 'https://api.openai.com/v1/responses');
          expect(request.headers['Authorization'], 'Bearer sk-test');
          expect(body['store'], false);
          expect(body['parallel_tool_calls'], false);
          expect(body['include'], contains('reasoning.encrypted_content'));
          expect(body['input'][0]['content'], 'How long is my boundary?');
          round++;
          if (round == 1) {
            expect(body['tool_choice']['name'], 'get_property_summary');
            return response([
              {
                'type': 'reasoning',
                'id': 'r1',
                'encrypted_content': 'opaque-test',
              },
              call('get_property_summary', 'summary', '{}'),
            ]);
          }
          final input = body['input'] as List;
          expect(
            input.any(
              (i) =>
                  i['type'] == 'reasoning' &&
                  i['encrypted_content'] == 'opaque-test',
            ),
            true,
          );
          final summary = input.firstWhere(
            (i) =>
                i['type'] == 'function_call_output' &&
                i['call_id'] == 'summary',
          );
          expect(jsonDecode(summary['output'])['property_name'], 'My pasture');
          if (round == 2) {
            return response([
              call('get_property_perimeter', 'perimeter', '{}'),
            ]);
          }
          final perimeter = jsonDecode(
            input.firstWhere(
              (i) =>
                  i['type'] == 'function_call_output' &&
                  i['call_id'] == 'perimeter',
            )['output'],
          );
          expect(perimeter['perimeter_m'], greaterThan(0));
          return response([
            {
              'type': 'message',
              'role': 'assistant',
              'content': [
                {
                  'type': 'output_text',
                  'text': 'Your boundary is a map-derived planning estimate.',
                },
              ],
            },
          ]);
        }),
      );
      final records = <CalculationRecord>[];
      final reply = await assistant.ask(
        property: exampleProperty(),
        history: [ChatMessage(role: 'user', text: 'How long is my boundary?')],
        apiKey: 'sk-test',
        model: 'test-model',
        onCalculation: records.add,
      );
      expect(round, 3);
      expect(reply.calculations, hasLength(2));
      expect(records, hasLength(2));
      expect(reply.text, contains('planning estimate'));
      assistant.dispose();
    },
  );
  test(
    'malformed tool arguments are returned as an error with the matching call ID',
    () async {
      var round = 0;
      final assistant = OpenAiAssistant(
        client: MockClient((request) async {
          round++;
          if (round == 1) {
            return response([call('get_property_summary', 'summary', '{}')]);
          }
          if (round == 2) {
            return response([
              call('calculate_gravel_volume', 'bad', 'not-json'),
            ]);
          }
          final input = (jsonDecode(request.body)['input'] as List);
          final bad = input.firstWhere(
            (i) => i['type'] == 'function_call_output' && i['call_id'] == 'bad',
          );
          expect(jsonDecode(bad['output'])['status'], 'error');
          return response([
            {
              'type': 'message',
              'content': [
                {
                  'type': 'output_text',
                  'text': 'What width and depth should I use?',
                },
              ],
            },
          ]);
        }),
      );
      final reply = await assistant.ask(
        property: exampleProperty(),
        history: [ChatMessage(role: 'user', text: 'Estimate gravel')],
        apiKey: 'sk-test',
        model: 'test-model',
      );
      expect(reply.text, contains('width and depth'));
      assistant.dispose();
    },
  );
  test(
    'HTTP failures and incomplete responses produce useful errors without leaking keys',
    () async {
      for (final status in [401, 403, 429, 400, 404, 503]) {
        final assistant = OpenAiAssistant(
          client: MockClient(
            (_) async =>
                http.Response('sensitive upstream response sk-secret', status),
          ),
        );
        await expectLater(
          assistant.ask(
            property: exampleProperty(),
            history: [],
            apiKey: 'sk-secret',
            model: 'test',
          ),
          throwsA(
            isA<AssistantException>().having(
              (e) => e.message,
              'message',
              isNot(contains('sk-secret')),
            ),
          ),
        );
        assistant.dispose();
      }
      final incomplete = OpenAiAssistant(
        client: MockClient((_) async => response([], status: 'incomplete')),
      );
      await expectLater(
        incomplete.ask(
          property: exampleProperty(),
          history: [],
          apiKey: 'sk-test',
          model: 'test',
        ),
        throwsA(
          isA<AssistantException>().having(
            (e) => e.message,
            'message',
            contains('did not finish'),
          ),
        ),
      );
      incomplete.dispose();
    },
  );
  test('runaway tool loops stop after a bounded number of requests', () async {
    var rounds = 0;
    final assistant = OpenAiAssistant(
      client: MockClient((_) async {
        rounds++;
        return response([call('get_property_summary', 's$rounds', '{}')]);
      }),
    );
    await expectLater(
      assistant.ask(
        property: exampleProperty(),
        history: [],
        apiKey: 'sk-test',
        model: 'test',
      ),
      throwsA(isA<AssistantException>()),
    );
    expect(rounds, 8);
    assistant.dispose();
  });
}
