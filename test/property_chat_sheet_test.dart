import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lando/controllers/property_chat_controller.dart';
import 'package:lando/services/assistant/assistant_provider.dart';
import 'package:lando/models/chat_message.dart';
import 'package:lando/services/assistant/openai_assistant.dart';
import 'package:lando/services/assistant/property_tools.dart';
import 'package:lando/widgets/assistant/property_chat_sheet.dart';
import 'package:lando/widgets/assistant/ai_settings_sheet.dart';
import 'support/assistant_fixtures.dart';
import 'property_chat_controller_test.dart' show FakeAssistant;

void main() {
  testWidgets(
    'AI key settings save securely, keep a saved key hidden and remove it',
    (tester) async {
      final repo = ChatMemoryRepository(), keys = MemoryKeyStore();
      Future<void> open() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) =>
                        AiSettingsSheet(keyStore: keys, repository: repo),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
      }

      await tester.binding.setSurfaceSize(const Size(390, 844));
      await open();
      await tester.enterText(
        find.byType(TextField).first,
        'sk-private-ui-test',
      );
      await tester.ensureVisible(find.text('Save AI settings'));
      await tester.tap(find.text('Save AI settings'));
      await tester.pumpAndSettle();
      expect(keys.key, 'sk-private-ui-test');
      expect(
        repo.preferences.values.join(),
        isNot(contains('sk-private-ui-test')),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );
      await tester.ensureVisible(find.text('Remove API key'));
      await tester.tap(find.text('Remove API key'));
      await tester.pumpAndSettle();
      expect(keys.key, isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.binding.setSurfaceSize(null);
    },
  );
  testWidgets(
    'chat sends questions, shows app results, and fits a small landscape screen',
    (tester) async {
      final repo = ChatMemoryRepository(),
          keys = MemoryKeyStore('sk-test'),
          property = exampleProperty();
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PropertyChatSheet(
              currentProperty: () => property,
              repository: repo,
              keyStore: keys,
              createAssistant: () => FakeAssistant(
                (p, h) async => AssistantReply(
                  'The acreage is shown in the app result below.',
                  [
                    CalculationRecord(
                      'get_property_area',
                      PropertyTools(p).execute('get_property_area', {}),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ask LandO'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'How many acres?');
      await tester.tap(find.byTooltip('Send question'));
      await tester.pumpAndSettle();
      expect(
        find.text('The acreage is shown in the app result below.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Property area'));
      await tester.tap(find.text('Property area'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Area (acres):'), findsOneWidget);
      await tester.binding.setSurfaceSize(const Size(667, 375));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.binding.setSurfaceSize(null);
      final history = PropertyChatController(
        propertyId: property.id,
        currentProperty: () => property,
        repository: repo,
        keyStore: keys,
      );
      await history.load();
      expect(history.messages, hasLength(2));
      history.dispose();
    },
  );
  testWidgets(
    'settings keep keys and models separate while switching between Gemini and OpenAI',
    (tester) async {
      final repo = ChatMemoryRepository(), keys = MemoryKeyStore('sk-existing');
      repo.preferences['openaiModel'] = 'openai-existing';
      await tester.binding.setSurfaceSize(const Size(390, 844));
      Future<void> open() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) =>
                        AiSettingsSheet(keyStore: keys, repository: repo),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
      }

      Future<void> select(AssistantProvider value) async {
        await tester.ensureVisible(
          find.byType(DropdownButtonFormField<AssistantProvider>),
        );
        await tester.tap(
          find.byType(DropdownButtonFormField<AssistantProvider>),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find
              .text(
                value == AssistantProvider.gemini
                    ? 'Gemini (Google)'
                    : 'OpenAI',
              )
              .last,
        );
        await tester.pumpAndSettle();
      }

      await open();
      await select(AssistantProvider.gemini);
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        AssistantProvider.gemini.defaultModel,
      );
      await tester.enterText(
        find.byType(TextField).first,
        'google-gemini-ui-test',
      );
      await tester.enterText(find.byType(TextField).last, 'gemini-custom');
      await select(AssistantProvider.openai);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        'openai-existing',
      );
      await select(AssistantProvider.gemini);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'google-gemini-ui-test',
      );
      await tester.ensureVisible(find.text('Save AI settings'));
      await tester.tap(find.text('Save AI settings'));
      await tester.pumpAndSettle();
      expect(keys.geminiKey, 'google-gemini-ui-test');
      expect(keys.key, 'sk-existing');
      expect(repo.preferences['aiProvider'], 'gemini');
      expect(repo.preferences['geminiModel'], 'gemini-custom');
      expect(repo.preferences['openaiModel'], 'openai-existing');
      expect(
        repo.preferences.values.join(),
        isNot(contains('google-gemini-ui-test')),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Gemini (Google)'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty,
      );
      await tester.ensureVisible(find.text('Remove API key'));
      await tester.tap(find.text('Remove API key'));
      await tester.pumpAndSettle();
      expect(keys.geminiKey, isNull);
      expect(keys.key, 'sk-existing');
      await tester.pumpWidget(const SizedBox());
      await tester.binding.setSurfaceSize(null);
    },
  );
}
