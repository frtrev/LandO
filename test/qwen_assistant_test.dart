import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart';
import 'package:lando/controllers/property_chat_controller.dart';
import 'package:lando/models/chat_message.dart';
import 'package:lando/services/assistant/local_model_store.dart';
import 'package:lando/services/assistant/local_web_search.dart';
import 'package:lando/services/assistant/qwen_assistant.dart';
import 'support/assistant_fixtures.dart';

class InstalledModels extends LocalModelStore {
  bool ready;
  InstalledModels({this.ready = true});
  @override
  Future<bool> isInstalled() async => ready;
  @override
  Future<String> installedPath() async => '/verified/model.gguf';
}

class InferenceFixture implements LocalInference {
  final List<LlamaCompletion> replies;
  final List<List<LlamaChatMessage>> prompts = [];
  final List<List<ToolDefinition>> offeredTools = [];
  bool closed = false;
  final requiredCalls = <bool>[];
  InferenceFixture(this.replies);
  @override
  Future<LlamaCompletion> complete(
    List<LlamaChatMessage> messages,
    List<ToolDefinition> tools, {
    bool requireTool = false,
  }) async {
    requiredCalls.add(requireTool);
    prompts.add(List.of(messages));
    offeredTools.add(List.of(tools));
    return replies.removeAt(0);
  }

  @override
  void cancel() {}
  @override
  Future<void> close() async {
    closed = true;
  }
}

class SearchFixture extends LocalWebSearch {
  bool fail;
  int calls = 0;
  SearchFixture({this.fail = false});
  @override
  Future<List<LocalSearchResult>> search(String query) async {
    calls++;
    if (fail) throw const FormatException('Unavailable');
    return [
      const LocalSearchResult(
        'Fence costs',
        'https://example.com/fence',
        'Published range: 10–20 per foot.',
      ),
    ];
  }
}

LlamaCompletion call(String name, Map<String, dynamic> args) => LlamaCompletion(
  text: '',
  toolCalls: [
    LlamaToolCallContent(
      id: 'call1',
      name: name,
      arguments: args,
      rawJson: '{}',
    ),
  ],
);
void main() {
  test(
    'local chat works with no key, persists and resumes the existing conversation',
    () async {
      final repo = ChatMemoryRepository(),
          keys = MemoryKeyStore(),
          models = InstalledModels();
      await repo.setPreference('aiProvider', 'qwen');
      await repo.setPreference('queryInternet', 'false');
      final runtime = InferenceFixture([
        call('get_property_area', {}),
        const LlamaCompletion(text: 'Here is your acreage.'),
      ]);
      final property = exampleProperty();
      final chat = PropertyChatController(
        propertyId: property.id,
        currentProperty: () => property,
        repository: repo,
        keyStore: keys,
        localModels: models,
        createAssistant: () =>
            QwenAssistant(models: models, loadInference: (_) async => runtime),
      );
      await chat.load();
      expect(chat.configured, true);
      await chat.send('How many acres?');
      expect(chat.error, isNull);
      expect(chat.messages, hasLength(2));
      expect(
        chat.messages.last.calculations.map((r) => r.tool),
        contains('get_property_area'),
      );
      expect(
        runtime.offeredTools.first.map((t) => t.name),
        isNot(contains('search_web')),
      );
      expect(runtime.closed, true);
      chat.dispose();
      final restored = PropertyChatController(
        propertyId: property.id,
        currentProperty: () => property,
        repository: repo,
        keyStore: keys,
        localModels: models,
      );
      await restored.load();
      expect(restored.messages.last.text, 'Here is your acreage.');
      models.ready = false;
      await restored.reloadConfiguration();
      expect(restored.configured, false);
      await restored.send('Hello');
      expect(restored.error, contains('Download'));
      restored.dispose();
    },
  );
  for (final fail in [false, true]) {
    test(
      'web results are sourced or failure disclosed (failure=$fail)',
      () async {
        final search = SearchFixture(fail: fail);
        final runtime = InferenceFixture([
          call('search_web', {'query': 'fence prices Tennessee'}),
          const LlamaCompletion(text: 'A planning estimate [1].'),
        ]);
        final assistant = QwenAssistant(
          models: InstalledModels(),
          search: search,
          loadInference: (_) async => runtime,
        );
        final reply = await assistant.ask(
          property: exampleProperty(),
          history: [
            ChatMessage(role: 'user', text: 'Find current fence prices'),
          ],
          apiKey: '',
          model: 'ignored',
        );
        expect(search.calls, 1);
        expect(runtime.requiredCalls.first, true);
        expect(runtime.offeredTools.first.single.name, 'search_web');
        expect(
          runtime.prompts.last.last.content,
          contains(fail ? 'unavailable' : 'Published range'),
        );
        if (fail) {
          expect(reply.research, isNull);
          expect(reply.text, contains('Internet search was unavailable'));
        } else {
          expect(
            reply.research!.citations.single.url,
            'https://example.com/fence',
          );
        }
      },
    );
  }
}
