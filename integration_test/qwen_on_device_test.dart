import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lando/controllers/property_chat_controller.dart';
import 'package:lando/services/assistant/assistant_provider.dart';
import 'package:lando/services/assistant/local_model_store.dart';
import 'package:lando/services/assistant/qwen_assistant.dart';
import 'package:llamadart/llamadart.dart';
import 'package:lando/widgets/assistant/ai_settings_sheet.dart';
import '../test/support/assistant_fixtures.dart';

class DiagnosticInference implements LocalInference {
  final LocalInference inner;
  DiagnosticInference(this.inner);
  @override
  Future<LlamaCompletion> complete(
    List<LlamaChatMessage> messages,
    List<ToolDefinition> tools, {
    bool requireTool = false,
  }) async {
    try {
      return await inner.complete(messages, tools, requireTool: requireTool);
    } catch (e, stack) {
      debugPrint('QWEN INFERENCE ERROR: $e\n$stack');
      rethrow;
    }
  }

  @override
  void cancel() => inner.cancel();
  @override
  Future<void> close() => inner.close();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('download, reuse and run real Qwen in a property conversation', (
    tester,
  ) async {
    final models = LocalModelStore();
    final repo = ChatMemoryRepository();
    final keys = MemoryKeyStore();
    await tester.runAsync(() async {
      expect(await models.download(), true, reason: models.error);
      expect(await models.isInstalled(), true);
      final path = await models.installedPath();
      expect(await models.download(), true);
      expect(await models.installedPath(), path);
      await repo.setPreference('aiProvider', AssistantProvider.qwen.name);
      await repo.setPreference('queryInternet', 'false');
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiSettingsSheet(
            repository: repo,
            keyStore: keys,
            localModels: models,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Ready for offline chat'), findsOneWidget);
    expect(find.text('Qwen API key'), findsNothing);
    final property = exampleProperty();
    final chat = PropertyChatController(
      propertyId: property.id,
      currentProperty: () => property,
      repository: repo,
      keyStore: keys,
      localModels: models,
      createAssistant: () => QwenAssistant(
        models: models,
        loadInference: (path) async {
          try {
            return DiagnosticInference(await NativeLocalInference.load(path));
          } catch (e, stack) {
            debugPrint('QWEN LOAD ERROR: $e\n$stack');
            rethrow;
          }
        },
      ),
    );
    await tester.runAsync(() async {
      await chat.load();
      expect(chat.configured, true);
      await chat.send('How many acres is my property? Give a brief answer.');
      expect(chat.error, isNull);
      expect(chat.messages.last.role, 'assistant');
      expect(chat.messages.last.text.toLowerCase(), contains('acre'));
      debugPrint('QWEN OFFLINE: ${chat.messages.last.text}');
      await repo.setPreference('queryInternet', 'true');
      await chat.reloadConfiguration();
      await chat.send(
        'Search the internet for average fence installation costs in Collierville Tennessee. Cite what you find.',
      );
      expect(chat.error, isNull);
      expect(chat.messages.last.role, 'assistant');
      final response = chat.messages.last;
      expect(
        response.research != null ||
            response.text.contains('Internet search was unavailable'),
        true,
        reason:
            'Must actually search or disclose search failure: ${response.text}',
      );
      debugPrint('QWEN WEB: ${response.text}');
      debugPrint(
        'QWEN SOURCES: ${response.research?.citations.map((c) => c.url).toList()}',
      );
      chat.dispose();
    });
  }, timeout: const Timeout(Duration(minutes: 12)));
}
