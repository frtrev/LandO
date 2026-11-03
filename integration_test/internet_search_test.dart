// Opt-in, billable live test. Pass LANDO_LIVE_GEMINI_KEY via a private
// --dart-define-from-file JSON, or use a key already saved in the simulator.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:lando/models/chat_message.dart';
import 'package:lando/services/assistant/api_key_store.dart';
import 'package:lando/services/assistant/assistant_provider.dart';
import 'package:lando/services/assistant/gemini_assistant.dart';
import 'package:lando/services/property_repository.dart';
import 'package:lando/widgets/assistant/property_chat_sheet.dart';
import 'package:lando/widgets/assistant/researched_answer.dart';
import '../test/support/assistant_fixtures.dart';

class DiagnosticClient extends http.BaseClient {
  final http.Client inner = http.Client();
  final String key;
  DiagnosticClient(this.key);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await inner.send(request);
    final bytes = await response.stream.toBytes();
    if (response.statusCode >= 400) {
      final body = jsonDecode(utf8.decode(bytes)) as Map;
      final error = body['error'] as Map? ?? {};
      final message = (error['message'] ?? 'No service error message')
          .toString()
          .replaceAll(key, '[redacted]');
      debugPrint('LIVE_SERVICE_ERROR HTTP ${response.statusCode}: $message');
    } else {
      debugPrint('LIVE_SERVICE_RESPONSE HTTP ${response.statusCode}');
    }
    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      headers: response.headers,
      request: response.request,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => inner.close();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('LandO researches fence and gutter pricing on a real service', (
    tester,
  ) async {
    const suppliedKey = String.fromEnvironment('LANDO_LIVE_GEMINI_KEY');
    final storedKey = await SecureApiKeyStore().read(
      provider: AssistantProvider.gemini,
    );
    final key = storedKey?.trim().isNotEmpty == true ? storedKey! : suppliedKey;
    expect(
      key.isNotEmpty,
      true,
      reason: 'Provide a Gemini key for this opt-in live test.',
    );
    final repository = await PropertyRepository.open(databasePath: ':memory:');
    await repository.setPreference('aiProvider', 'gemini');
    await repository.setPreference('queryInternet', 'true');
    final keys = MemoryKeyStore(null, key);
    final property = exampleProperty();
    final questions = [
      'I am in Austin, Texas. For a 6-foot wood privacy fence with posts spaced 8 ft apart, look up typical installed cost per linear foot in my area today. Give a sourced price range, materials versus labor where available, and a reliability disclaimer. Do not calculate a property total yet.',
      'Look up typical installed seamless aluminum gutter costs per linear foot in Austin, Texas. My gutter run is 150 ft. Cite sources and explain uncertainty. Do not infer gutter length from my parcel boundary.',
    ];
    for (var i = 0; i < questions.length; i++) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PropertyChatSheet(
              key: ValueKey(i),
              currentProperty: () => property,
              repository: repository,
              keyStore: keys,
              createAssistant: () =>
                  GeminiAssistant(client: DiagnosticClient(key)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (i > 0) {
        await tester.tap(find.byTooltip('New conversation'));
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byType(TextField), questions[i]);
      await tester.tap(find.byTooltip('Send question'));
      await tester.pump(const Duration(milliseconds: 100));
      final deadline = DateTime.now().add(const Duration(seconds: 125));
      while (tester
                  .widget<IconButton>(
                    find.byWidgetPredicate(
                      (widget) =>
                          widget is IconButton &&
                          widget.tooltip == 'Send question',
                    ),
                  )
                  .onPressed ==
              null &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      await tester.pumpAndSettle();
      final scroll = tester.widget<ListView>(find.byType(ListView)).controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final answers = tester
          .widgetList<ResearchedAnswer>(find.byType(ResearchedAnswer))
          .where((w) => w.message.role == 'assistant')
          .toList();
      expect(
        answers,
        isNotEmpty,
        reason:
            'The live question must return an assistant answer. Visible errors: ${tester.widgetList<Text>(find.byType(Text)).map((w) => w.data).whereType<String>().where((t) => t.startsWith("LandO could") || t.startsWith("Could not")).join("; ")}',
      );
      final ChatMessage answer = answers.last.message;
      expect(
        answer.research,
        isNotNull,
        reason: 'A pricing question must actually search the internet.',
      );
      expect(
        answer.research!.citations,
        isNotEmpty,
        reason: 'The live answer must include service-provided source links.',
      );
      expect(answer.text.length, greaterThan(80));
      expect(find.text(ResearchedAnswer.shortDisclaimer), findsOneWidget);
      await tester.tap(find.text('View details'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Internet research'), findsOneWidget);
      expect(
        find.textContaining('Planning estimate based on online information'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Close details'));
      await tester.pumpAndSettle();
      debugPrint(
        'LIVE_SEARCH_PASSED question=${i + 1}, citations=${answer.research!.citations.length}',
      );
      debugPrint('LIVE_ANSWER: ${answer.text}');
      debugPrint(
        'LIVE_LOCAL_TOOLS: ${answer.calculations.map((c) => c.tool).join(", ")}',
      );
    }
    await tester.pumpWidget(const SizedBox());
    await repository.db.close();
  }, timeout: const Timeout(Duration(minutes: 6)));
}
