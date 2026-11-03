import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/chat_message.dart';
import '../../models/property.dart';
import 'assistant_instructions.dart';
import 'lando_assistant.dart';
import 'property_tools.dart';
import 'research_collector.dart';

/// Gemini Developer API (Generative Language API), with local read-only tools.
/// Credentials never appear in URLs, error messages, or conversation storage.
class GeminiAssistant implements LandoAssistant {
  final http.Client client;
  GeminiAssistant({http.Client? client}) : client = client ?? http.Client();
  static List<Map<String, dynamic>> get functionDeclarations => [
    for (final tool in PropertyTools.definitions)
      {
        'name': tool['name'],
        'description': tool['description'],
        'parametersJsonSchema': tool['parameters'],
      },
  ];
  @override
  Future<AssistantReply> ask({
    required Property property,
    required List<ChatMessage> history,
    required String apiKey,
    required String model,
    bool queryInternet = true,
    void Function(CalculationRecord)? onCalculation,
  }) async {
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{0,99}$').hasMatch(model)) {
      throw const AssistantException(
        'Check your LandO configuration in AI settings.',
      );
    }
    final tools = PropertyTools(property);
    final contents = <Map<String, dynamic>>[
      for (final message in history.skip(
        history.length > 24 ? history.length - 24 : 0,
      ))
        {
          'role': message.role == 'assistant' ? 'model' : 'user',
          'parts': [
            {'text': message.contextText},
          ],
        },
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
              Uri.https(
                'generativelanguage.googleapis.com',
                '/v1beta/models/$model:generateContent',
              ),
              headers: {
                'x-goog-api-key': apiKey,
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'systemInstruction': {
                  'parts': [
                    {'text': instructionsForSearch(queryInternet)},
                  ],
                },
                'contents': contents,
                'tools': [
                  {'functionDeclarations': functionDeclarations},
                  if (queryInternet && round > 0) {'googleSearch': {}},
                ],
                // Mixed search/function tools require context circulation and
                // VALIDATED mode. Replay the complete content below, including
                // hosted tool calls/results and their signatures.
                'toolConfig': {
                  if (queryInternet && round > 0)
                    'includeServerSideToolInvocations': true,
                  'functionCallingConfig': round == 0
                      ? {
                          'mode': 'ANY',
                          'allowedFunctionNames': ['get_property_summary'],
                        }
                      : {'mode': queryInternet ? 'VALIDATED' : 'AUTO'},
                },
                'generationConfig': {
                  'maxOutputTokens': 3000,
                  'candidateCount': 1,
                },
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
        final candidates = body['candidates'] as List? ?? [];
        if (candidates.isEmpty) {
          throw const AssistantException(
            'LandO could not answer this question. Try rephrasing it.',
          );
        }
        final candidate = Map<String, dynamic>.from(candidates.first as Map);
        final finish = candidate['finishReason'];
        if (finish != null && finish != 'STOP') {
          throw const AssistantException(
            'LandO did not finish this answer. Try a shorter or rephrased question.',
          );
        }
        final content = Map<String, dynamic>.from(candidate['content'] as Map);
        final parts = (content['parts'] as List)
            .map((part) => Map<String, dynamic>.from(part as Map))
            .toList();
        // Keep the entire model content verbatim: function-call parts can carry
        // thoughtSignature and call IDs required by subsequent Gemini requests.
        contents.add(content);
        final visibleText = parts
            .where((p) => p['text'] is String && p['thought'] != true)
            .map((p) => p['text'] as String)
            .join('\n\n');
        if (queryInternet) research.gemini(candidate, visibleText);
        final calls = parts
            .where((part) => part['functionCall'] != null)
            .toList();
        if (calls.isEmpty) {
          final text = parts
              .where(
                (part) => part['text'] is String && part['thought'] != true,
              )
              .map((part) => part['text'] as String)
              .join('\n\n');
          if (text.trim().isEmpty || !summaryRead) {
            throw const AssistantException(
              'LandO could not produce an answer grounded in this property. Please try again.',
            );
          }
          return AssistantReply(text, records, research: research.result);
        }
        final results = <Map<String, dynamic>>[];
        for (final part in calls) {
          if (++callsExecuted > 16) {
            throw const AssistantException(
              'This request needs too many steps. Ask one project question at a time.',
            );
          }
          final call = Map<String, dynamic>.from(part['functionCall'] as Map);
          final name = call['name'] as String;
          Map<String, dynamic> result;
          try {
            result = tools.execute(
              name,
              Map<String, dynamic>.from((call['args'] ?? {}) as Map),
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
          results.add({
            'functionResponse': {
              'name': name,
              if (call['id'] != null) 'id': call['id'],
              'response': result,
            },
          });
        }
        contents.add({'role': 'user', 'parts': results});
      }
      throw const AssistantException(
        'LandO reached its calculation limit. Try one question at a time.',
      );
    } on AssistantException {
      rethrow;
    } on TimeoutException {
      throw const AssistantException(
        'LandO timed out. Check your connection and try again.',
      );
    } on http.ClientException {
      throw const AssistantException(
        'Could not reach LandO. Check your connection and try again.',
      );
    } on Object {
      throw const AssistantException(
        'Could not read the LandO response. Please try again.',
      );
    }
  }

  @override
  void dispose() => client.close();
}
