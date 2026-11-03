import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lando/controllers/property_chat_controller.dart';
import 'package:lando/models/chat_message.dart';
import 'package:lando/models/web_research.dart';
import 'package:lando/services/assistant/openai_assistant.dart';
import 'package:lando/services/assistant/gemini_assistant.dart';
import 'package:lando/services/assistant/research_collector.dart';
import 'package:lando/widgets/assistant/researched_answer.dart';
import 'support/assistant_fixtures.dart';
import 'property_chat_controller_test.dart' show FakeAssistant;
import 'openai_assistant_test.dart' show call, response;
import 'gemini_assistant_test.dart' show geminiResponse;

void main() {
  for (final enabled in [true, false]) {
    test(
      'OpenAI search ${enabled ? 'enabled' : 'disabled'} preserves local tools and captures actual citations',
      () async {
        var round = 0;
        final assistant = OpenAiAssistant(
          client: MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            round++;
            final tools = body['tools'] as List;
            expect(
              tools.any((t) => t['type'] == 'web_search'),
              enabled && round > 1,
            );
            expect(
              body['instructions'],
              contains(
                enabled
                    ? 'Internet search is available'
                    : 'Internet search is disabled',
              ),
            );
            if (round == 1) {
              return response([call('get_property_summary', 'summary', '{}')]);
            }
            if (round == 2) {
              return response([
                call('get_property_perimeter', 'perimeter', '{}'),
              ]);
            }
            return response([
              if (enabled)
                {
                  'type': 'web_search_call',
                  'status': 'completed',
                  'id': 'search1',
                  'action': {'type': 'search', 'query': 'fence installed cost'},
                },
              {
                'type': 'message',
                'role': 'assistant',
                'content': [
                  {
                    'type': 'output_text',
                    'text': 'Published fence pricing varies.',
                    'annotations': [
                      if (enabled)
                        {
                          'type': 'url_citation',
                          'start_index': 0,
                          'end_index': 31,
                          'url': 'https://example.com/fence',
                          'title': 'Fence pricing',
                        },
                    ],
                  },
                ],
              },
            ]);
          }),
        );
        final reply = await assistant.ask(
          property: exampleProperty(),
          history: [ChatMessage(role: 'user', text: 'Fence cost?')],
          apiKey: 'sk-test',
          model: 'test',
          queryInternet: enabled,
        );
        expect(round, 3);
        expect(reply.calculations.map((c) => c.tool), [
          'get_property_summary',
          'get_property_perimeter',
        ]);
        if (enabled) {
          expect(
            reply.research!.citations.single.url,
            'https://example.com/fence',
          );
          expect(reply.research!.citations.single.end, reply.text.length);
        } else {
          expect(reply.research, isNull);
        }
        assistant.dispose();
      },
    );

    test(
      'Gemini search ${enabled ? 'enabled' : 'disabled'} retains local tools, annotations and search suggestions',
      () async {
        var round = 0;
        const text = 'A café fence estimate varies.';
        final assistant = GeminiAssistant(
          client: MockClient((request) async {
            expect(request.url.query, isEmpty);
            expect(request.headers['x-goog-api-key'], 'google-test');
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            round++;
            expect(
              (body['tools'] as List).any((t) => t.containsKey('googleSearch')),
              enabled && round > 1,
            );
            expect(
              body['toolConfig']['includeServerSideToolInvocations'],
              enabled && round > 1 ? true : isNull,
            );
            if (round > 1) {
              expect(
                body['toolConfig']['functionCallingConfig']['mode'],
                enabled ? 'VALIDATED' : 'AUTO',
              );
            }
            if (round == 1) {
              return geminiResponse([
                {
                  'functionCall': {'name': 'get_property_summary', 'args': {}},
                },
              ]);
            }
            return http.Response(
              jsonEncode({
                'candidates': [
                  {
                    'finishReason': 'STOP',
                    'content': {
                      'role': 'model',
                      'parts': [
                        {'text': text},
                      ],
                    },
                    if (enabled)
                      'groundingMetadata': {
                        'webSearchQueries': ['fence cost'],
                        'searchEntryPoint': {
                          'renderedContent': '<div>Search suggestions</div>',
                        },
                        'groundingChunks': [
                          {
                            'web': {
                              'uri': 'https://example.com/cost',
                              'title': 'Cost guide',
                            },
                          },
                        ],
                        'groundingSupports': [
                          {
                            'segment': {
                              'startIndex': 0,
                              'endIndex': utf8.encode(text).length,
                            },
                            'groundingChunkIndices': [0],
                          },
                        ],
                      },
                  },
                ],
              }),
              200,
            );
          }),
        );
        final reply = await assistant.ask(
          property: exampleProperty(),
          history: [ChatMessage(role: 'user', text: 'Fence cost?')],
          apiKey: 'google-test',
          model: 'gemini-test',
          queryInternet: enabled,
        );
        expect(reply.text, text);
        if (enabled) {
          expect(reply.research!.citations.last.end, text.length);
          expect(
            reply.research!.searchSuggestions.single,
            '<div>Search suggestions</div>',
          );
        } else {
          expect(reply.research, isNull);
        }
        assistant.dispose();
      },
    );
  }

  test(
    'unsupported internet configuration fails clearly without an automatic billable retry',
    () async {
      for (final gemini in [false, true]) {
        var calls = 0;
        final client = MockClient((_) async {
          calls++;
          return http.Response('secret-key-in-error', 400);
        });
        final LandoAssistant assistant = gemini
            ? GeminiAssistant(client: client)
            : OpenAiAssistant(client: client);
        await expectLater(
          assistant.ask(
            property: exampleProperty(),
            history: [],
            apiKey: 'secret-key',
            model: 'custom',
          ),
          throwsA(
            isA<AssistantException>().having(
              (e) => e.message,
              'helpful error',
              allOf(
                contains('Query the internet'),
                isNot(contains('secret-key')),
              ),
            ),
          ),
        );
        expect(calls, 1);
        assistant.dispose();
      }
    },
  );

  test(
    'source annotations survive save/reopen and legacy messages still load',
    () async {
      final research = WebResearch(
        checkedAt: DateTime.utc(2026, 11, 3),
        citations: [
          const WebCitation(
            start: 0,
            end: 4,
            url: 'https://example.com/cost',
            title: 'Cost guide',
          ),
        ],
      );
      final repo = ChatMemoryRepository(), property = exampleProperty();
      PropertyChatController create() => PropertyChatController(
        propertyId: property.id,
        currentProperty: () => property,
        repository: repo,
        keyStore: MemoryKeyStore('sk-test'),
        createAssistant: () => FakeAssistant(
          (p, h) async =>
              AssistantReply('Cost varies.', [], research: research),
        ),
      );
      var chat = create();
      await chat.load();
      await chat.send('Cost?');
      chat.dispose();
      chat = create();
      await chat.load();
      final message = chat.messages.last;
      expect(message.research!.checkedAt, research.checkedAt);
      expect(
        message.research!.citations.single.url,
        'https://example.com/cost',
      );
      expect(message.contextText, contains('not a fresh lookup'));
      expect(
        ChatMessage.fromJson({
          'role': 'assistant',
          'text': 'Legacy',
          'created': '2026-01-01T00:00:00Z',
        }).research,
        isNull,
      );
      chat.dispose();
    },
  );

  test(
    'invalid citation URLs and indices cannot create clickable source content',
    () {
      final collector = ResearchCollector();
      collector.openAi([
        {
          'type': 'message',
          'content': [
            {
              'type': 'output_text',
              'text': 'Costs',
              'annotations': [
                {
                  'type': 'url_citation',
                  'start_index': 0,
                  'end_index': 5,
                  'url': 'javascript:alert(1)',
                },
                {
                  'type': 'url_citation',
                  'start_index': -1,
                  'end_index': 5,
                  'url': 'https://example.com',
                },
                {
                  'type': 'url_citation',
                  'start_index': 0,
                  'end_index': 500,
                  'url': 'https://example.com',
                },
              ],
            },
          ],
        },
      ]);
      expect(collector.result, isNull);
      collector.openAi([
        {'type': 'web_search_call', 'status': 'completed'},
      ]);
      expect(collector.result!.citations, isEmpty);
    },
  );

  testWidgets(
    'researched answers show clickable inline sources, date and reliability note without model branding',
    (tester) async {
      final message = ChatMessage(
        role: 'assistant',
        text: 'Cost varies.',
        research: WebResearch(
          checkedAt: DateTime.utc(2026, 11, 3, 12),
          citations: [
            const WebCitation(
              start: 0,
              end: 12,
              url: 'https://example.com/cost',
              title: 'Cost guide',
            ),
          ],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ResearchedAnswer(message: message),
            ),
          ),
        ),
      );
      expect(find.textContaining('Cost guide'), findsNothing);
      expect(find.text(WebResearch.disclaimer), findsNothing);
      expect(find.text(ResearchedAnswer.shortDisclaimer), findsOneWidget);
      await tester.tap(find.text('Full disclaimer'));
      await tester.pumpAndSettle();
      expect(find.text(ResearchedAnswer.fullDisclaimer), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      final text = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(text.textSpan!.toPlainText(), contains('[1]'));
      await tester.tap(find.text('View details'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Cost guide'), findsOneWidget);
      expect(find.text(WebResearch.disclaimer), findsOneWidget);
      expect(find.textContaining('Internet research'), findsOneWidget);
      expect(find.textContaining('Gemini'), findsNothing);
      expect(find.textContaining('OpenAI'), findsNothing);
      await tester.binding.setSurfaceSize(const Size(667, 375));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.binding.setSurfaceSize(null);
    },
  );
}
