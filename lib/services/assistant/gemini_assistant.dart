import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/chat_message.dart';
import '../../models/property.dart';
import 'assistant_instructions.dart';
import 'lando_assistant.dart';
import 'property_tools.dart';

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
    void Function(CalculationRecord)? onCalculation,
  }) async {
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{0,99}$').hasMatch(model)) {
      throw const AssistantException(
        'Enter a valid Gemini model ID in AI settings.',
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
            {'text': message.text},
          ],
        },
    ];
    final records = <CalculationRecord>[];
    final timer = Stopwatch()..start();
    var summaryRead = false, callsExecuted = 0;
    try {
      for (var round = 0; round < 8; round++) {
        final remaining = 120000 - timer.elapsedMilliseconds;
        if (remaining <= 0) {
          throw const AssistantException(
            'Gemini took too long to answer. Try a more specific question.',
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
                    {'text': assistantInstructions},
                  ],
                },
                'contents': contents,
                'tools': [
                  {'functionDeclarations': functionDeclarations},
                ],
                'toolConfig': {
                  'functionCallingConfig': round == 0
                      ? {
                          'mode': 'ANY',
                          'allowedFunctionNames': ['get_property_summary'],
                        }
                      : {'mode': 'AUTO'},
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
              'Gemini rejected this key or its permissions. Check the Gemini key and Generative Language API access in AI settings.',
            429 =>
              'Gemini reports a quota or rate limit. Check your Google project usage and billing, then try again.',
            400 || 404 =>
              'Gemini could not use this key, model or request. Check your Gemini model and API access in AI settings.',
            _ => 'Gemini is unavailable right now. Please try again later.',
          });
        }
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final candidates = body['candidates'] as List? ?? [];
        if (candidates.isEmpty) {
          throw const AssistantException(
            'Gemini could not answer this question. Try rephrasing it.',
          );
        }
        final candidate = Map<String, dynamic>.from(candidates.first as Map);
        final finish = candidate['finishReason'];
        if (finish != null && finish != 'STOP') {
          throw const AssistantException(
            'Gemini did not finish this answer. Try a shorter or rephrased question.',
          );
        }
        final content = Map<String, dynamic>.from(candidate['content'] as Map);
        final parts = (content['parts'] as List)
            .map((part) => Map<String, dynamic>.from(part as Map))
            .toList();
        // Keep the entire model content verbatim: function-call parts can carry
        // thoughtSignature and call IDs required by subsequent Gemini requests.
        contents.add(content);
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
              'Gemini could not produce an answer grounded in this property. Please try again.',
            );
          }
          return AssistantReply(text, records);
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
        'Gemini reached its calculation limit. Try one question at a time.',
      );
    } on AssistantException {
      rethrow;
    } on TimeoutException {
      throw const AssistantException(
        'Gemini timed out. Check your connection and try again.',
      );
    } on http.ClientException {
      throw const AssistantException(
        'Could not reach Gemini. Check your connection and try again.',
      );
    } on Object {
      throw const AssistantException(
        'Could not read the Gemini response. Please try again.',
      );
    }
  }

  @override
  void dispose() => client.close();
}
