import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/chat_message.dart';
import '../../models/property.dart';
import 'property_tools.dart';
import 'research_collector.dart';
import 'lando_assistant.dart';
import 'assistant_instructions.dart';
export 'lando_assistant.dart';

class OpenAiAssistant implements LandoAssistant {
  final http.Client client;
  OpenAiAssistant({http.Client? client}) : client = client ?? http.Client();
  static const instructions = assistantInstructions;
  @override
  Future<AssistantReply> ask({
    required Property property,
    required List<ChatMessage> history,
    required String apiKey,
    required String model,
    bool queryInternet = true,
    void Function(CalculationRecord)? onCalculation,
  }) async {
    final tools = PropertyTools(property);
    final input = <Map<String, dynamic>>[
      for (final message in history.skip(
        history.length > 24 ? history.length - 24 : 0,
      ))
        {'role': message.role, 'content': message.contextText},
    ];
    final records = <CalculationRecord>[];
    final research = ResearchCollector();
    final timer = Stopwatch()..start();
    var summaryRead = false, callsExecuted = 0;
    try {
      for (var round = 0; round < 8; round++) {
        final remaining = 120000 - timer.elapsedMilliseconds;
        if (remaining <= 0) {
          throw const AssistantException(
            'LandO took too long to answer. Try a more specific question.',
          );
        }
        final response = await client
            .post(
              Uri.parse('https://api.openai.com/v1/responses'),
              headers: {
                'Authorization': 'Bearer $apiKey',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'model': model,
                'instructions': instructionsForSearch(queryInternet),
                'input': input,
                'tools': [
                  ...PropertyTools.definitions,
                  if (queryInternet && round > 0) {'type': 'web_search'},
                ],
                'tool_choice': round == 0
                    ? {'type': 'function', 'name': 'get_property_summary'}
                    : 'auto',
                'parallel_tool_calls': false,
                'store': false,
                'include': ['reasoning.encrypted_content'],
                'reasoning': {'effort': 'low'},
                'max_output_tokens': 3000,
              }),
            )
            .timeout(
              Duration(milliseconds: remaining < 45000 ? remaining : 45000),
            );
        if (response.statusCode != 200) {
          throw AssistantException(switch (response.statusCode) {
            401 || 403 =>
              'LandO could not authenticate. Check your API key and service access in AI settings.',
            429 =>
              'LandO reached a usage limit. Check your configured service usage and billing, then try again.',
            400 || 404 =>
              queryInternet
                  ? 'LandO could not complete this request with internet search enabled. Check search support and API access in AI settings, or turn off Query the internet.'
                  : 'LandO could not complete this request. Check your configuration and API access in AI settings.',
            _ => 'LandO is unavailable right now. Please try again later.',
          });
        }
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['status'] != 'completed') {
          throw const AssistantException(
            'The answer did not finish. Try a shorter, more specific question.',
          );
        }
        final output = (body['output'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        // Replay every output item, including encrypted reasoning, for stateless
        // tool continuation. No previous_response_id/server-side storage is used.
        input.addAll(output);
        if (queryInternet) research.openAi(output);
        final calls = output
            .where((item) => item['type'] == 'function_call')
            .toList();
        if (calls.isEmpty) {
          final text = <String>[];
          for (final item in output.where(
            (item) => item['type'] == 'message',
          )) {
            for (final content in (item['content'] as List? ?? [])) {
              if (content['type'] == 'output_text') {
                text.add(content['text'] as String);
              }
              if (content['type'] == 'refusal') {
                text.add(content['refusal'] as String);
              }
            }
          }
          if (text.isEmpty || !summaryRead) {
            throw const AssistantException(
              'LandO could not produce an answer grounded in this property. Please try again.',
            );
          }
          return AssistantReply(
            text.join('\n\n'),
            records,
            research: research.result,
          );
        }
        for (final call in calls) {
          if (++callsExecuted > 16) {
            throw const AssistantException(
              'This request needs too many steps. Ask one project question at a time.',
            );
          }
          final name = call['name'] as String;
          Map<String, dynamic> result;
          try {
            result = tools.execute(
              name,
              Map<String, dynamic>.from(
                jsonDecode(call['arguments'] as String) as Map,
              ),
            );
          } on Object {
            result = {
              'status': 'error',
              'error':
                  'Invalid tool arguments. Ask for the missing inputs or retry with valid arguments.',
            };
          }
          if (name == 'get_property_summary' && result['status'] == 'ok') {
            summaryRead = true;
          }
          final record = CalculationRecord(name, result);
          records.add(record);
          onCalculation?.call(record);
          input.add({
            'type': 'function_call_output',
            'call_id': call['call_id'],
            'output': jsonEncode(result),
          });
        }
      }
      throw const AssistantException(
        'LandO reached its calculation limit. Try one question at a time.',
      );
    } on AssistantException {
      rethrow;
    } on TimeoutException {
      throw const AssistantException(
        'The request timed out. Check your connection and try again.',
      );
    } on http.ClientException {
      throw const AssistantException(
        'Could not reach LandO. Check your connection and try again.',
      );
    } on Object {
      throw const AssistantException(
        'Could not read the assistant response. Please try again.',
      );
    }
  }

  @override
  void dispose() => client.close();
}
