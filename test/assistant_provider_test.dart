import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:lando/controllers/property_chat_controller.dart';
import 'package:lando/models/chat_message.dart';
import 'package:lando/models/property.dart';
import 'package:lando/services/assistant/api_key_store.dart';
import 'package:lando/services/assistant/assistant_provider.dart';
import 'package:lando/services/assistant/lando_assistant.dart';
import 'support/assistant_fixtures.dart';

class CaptureAssistant implements LandoAssistant {
  String? key, model;
  int calls = 0;
  @override
  Future<AssistantReply> ask({
    required Property property,
    required List<ChatMessage> history,
    required String apiKey,
    required String model,
    void Function(CalculationRecord)? onCalculation,
  }) async {
    calls++;
    key = apiKey;
    this.model = model;
    return const AssistantReply('App-calculated result.', []);
  }

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'secure storage preserves legacy OpenAI slot and keeps Gemini credentials isolated',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        SecureApiKeyStore.keyName: 'sk-legacy',
      });
      final store = SecureApiKeyStore();
      expect(await store.read(), 'sk-legacy');
      await store.save('google-private', provider: AssistantProvider.gemini);
      expect(await store.read(), 'sk-legacy');
      expect(
        await store.read(provider: AssistantProvider.gemini),
        'google-private',
      );
      await store.delete(provider: AssistantProvider.gemini);
      expect(await store.read(provider: AssistantProvider.gemini), isNull);
      expect(await store.read(), 'sk-legacy');
    },
  );
  test(
    'Gemini works with no OpenAI key and switching providers uses only the selected credentials and model',
    () async {
      final property = exampleProperty(),
          repo = ChatMemoryRepository(),
          keys = MemoryKeyStore(null, 'google-private');
      repo.preferences['aiProvider'] = 'gemini';
      repo.preferences['geminiModel'] = 'gemini-custom';
      repo.preferences['openaiModel'] = 'openai-custom';
      final capture = CaptureAssistant();
      final chat = PropertyChatController(
        propertyId: property.id,
        currentProperty: () => property,
        repository: repo,
        keyStore: keys,
        createAssistant: () => capture,
      );
      await chat.load();
      expect(chat.provider, AssistantProvider.gemini);
      expect(chat.configured, true);
      await chat.send('Area?');
      expect(capture.key, 'google-private');
      expect(capture.model, 'gemini-custom');
      expect(chat.messages.last.provider, 'Gemini');
      repo.preferences['aiProvider'] = 'openai';
      await chat.reloadConfiguration();
      expect(chat.configured, false);
      await chat.send('Follow up?');
      expect(capture.calls, 1);
      expect(chat.error, contains('OpenAI API key'));
      keys.key = 'sk-openai';
      await chat.reloadConfiguration();
      await chat.send('Follow up?');
      expect(capture.calls, 2);
      expect(capture.key, 'sk-openai');
      expect(capture.model, 'openai-custom');
      expect(chat.messages.last.provider, 'OpenAI');
      expect(chat.messages[1].provider, 'Gemini');
      expect(repo.preferences.values.join(), isNot(contains('google-private')));
      expect(repo.preferences.values.join(), isNot(contains('sk-openai')));
      chat.dispose();
    },
  );
}
