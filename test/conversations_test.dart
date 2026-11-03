import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lando/controllers/property_chat_controller.dart';
import 'package:lando/models/chat_message.dart';
import 'package:lando/models/chat_conversation.dart';
import 'package:lando/services/assistant/lando_assistant.dart';
import 'package:lando/services/property_repository.dart';
import 'support/assistant_fixtures.dart';
import 'property_chat_controller_test.dart' show FakeAssistant;

class FailingChatRepository extends ChatMemoryRepository {
  bool fail = false;
  @override
  Future<void> setPreference(String key, String value) async {
    if (fail && key.startsWith('chat:')) {
      throw StateError('Disk full');
    }
    await super.setPreference(key, value);
  }
}

void main() {
  sqfliteFfiInit();
  PropertyChatController make(
    PropertyRepository repo, {
    String id = 'property',
    LandoAssistant Function()? assistant,
  }) => PropertyChatController(
    propertyId: id,
    currentProperty: () => exampleProperty(id: id),
    repository: repo,
    keyStore: MemoryKeyStore('sk-test'),
    createAssistant:
        assistant ??
        () => FakeAssistant(
          (p, h) async => const AssistantReply('Saved answer', []),
        ),
  );
  test(
    'legacy chats migrate once with all messages, dates, providers and calculation records intact',
    () async {
      final repo = ChatMemoryRepository();
      final original = List.generate(
        50,
        (i) => ChatMessage(
          role: i.isEven ? 'user' : 'assistant',
          text: i == 0 ? 'Plan my garden' : 'Message $i',
          created: DateTime.utc(2020, 1, 1).add(Duration(minutes: i)),
          provider: i.isOdd ? 'Gemini' : null,
          calculations: i.isOdd
              ? [
                  const CalculationRecord('get_property_area', {
                    'area_acres': 2.5,
                  }),
                ]
              : [],
        ),
      );
      repo.preferences['chat:property'] = jsonEncode(
        original.map((m) => m.toJson()).toList(),
      );
      var chat = make(repo);
      await chat.load();
      expect(
        chat.messages.map((m) => m.toJson()),
        original.map((m) => m.toJson()),
      );
      expect(chat.activeConversation.title, 'Plan my garden');
      expect(chat.activeConversation.created, original.first.created);
      final id = chat.activeConversation.id;
      chat.dispose();
      chat = make(repo);
      await chat.load();
      expect(chat.activeConversation.id, id);
      expect(chat.conversations, hasLength(1));
      expect(chat.messages, hasLength(50));
      expect(jsonDecode(repo.preferences['chat:property']!)['version'], 2);
      chat.dispose();
    },
  );
  test(
    'new conversations isolate prompts, keep full history, and restore the last selected chat',
    () async {
      final repo = ChatMemoryRepository();
      final inputs = <List<String>>[];
      PropertyChatController create() => make(
        repo,
        assistant: () => FakeAssistant((p, h) async {
          inputs.add(h.map((m) => m.text).toList());
          return const AssistantReply('Answer', []);
        }),
      );
      var chat = create();
      await chat.load();
      await chat.send('Plan a garden');
      final gardenId = chat.activeConversation.id;
      await chat.newConversation();
      expect(chat.messages, isEmpty);
      await chat.send('Plan a fence');
      final fenceId = chat.activeConversation.id;
      expect(inputs.last, ['Plan a fence']);
      expect(chat.conversations, hasLength(2));
      await chat.openConversation(gardenId);
      await chat.send('Use the same garden area');
      expect(inputs.last, [
        'Plan a garden',
        'Answer',
        'Use the same garden area',
      ]);
      expect(inputs.last, isNot(contains('Plan a fence')));
      chat.dispose();
      chat = create();
      await chat.load();
      expect(chat.activeConversation.id, gardenId);
      expect(chat.messages.last.text, 'Answer');
      expect(chat.conversations.first.id, gardenId);
      await chat.openConversation(fenceId);
      expect(chat.messages.first.text, 'Plan a fence');
      for (var i = 0; i < 22; i++) {
        await chat.send('Follow up $i');
      }
      expect(chat.messages, hasLength(46));
      chat.dispose();
      chat = create();
      await chat.load();
      expect(chat.activeConversation.id, fenceId);
      expect(chat.messages, hasLength(46));
      final other = make(repo, id: 'another-property');
      await other.load();
      expect(other.messages, isEmpty);
      expect(other.conversations, hasLength(1));
      other.dispose();
      chat.dispose();
    },
  );
  test(
    'renaming, clearing and deletion affect only their target conversation',
    () async {
      final repo = ChatMemoryRepository();
      final controller = make(repo);
      await controller.load();
      await controller.send('Original topic');
      final first = controller.activeConversation.id;
      await controller.renameConversation(first, 'Garden planning');
      await controller.newConversation();
      await controller.send('Fence topic');
      final second = controller.activeConversation.id;
      await controller.clearHistory();
      expect(controller.messages, isEmpty);
      expect(
        controller.conversations.firstWhere((c) => c.id == first).messages,
        hasLength(2),
      );
      await controller.openConversation(first);
      expect(controller.activeConversation.title, 'Garden planning');
      await controller.deleteConversation(second);
      expect(controller.activeConversation.id, first);
      expect(controller.messages, hasLength(2));
      await controller.deleteConversation(first);
      expect(controller.conversations, hasLength(1));
      expect(controller.messages, isEmpty);
      expect(controller.activeConversation.id, isNot(first));
      controller.dispose();
    },
  );
  test(
    'failed conversation writes roll back selection, rename and deletion without erasing storage',
    () async {
      final repo = FailingChatRepository();
      final controller = make(repo);
      await controller.load();
      await controller.send('Garden');
      final first = controller.activeConversation.id;
      await controller.newConversation();
      final second = controller.activeConversation.id;
      final saved = repo.preferences['chat:property'];
      repo.fail = true;
      expect(await controller.newConversation(), false);
      expect(controller.activeConversation.id, second);
      expect(controller.conversations, hasLength(2));
      expect(await controller.openConversation(first), false);
      expect(controller.activeConversation.id, second);
      expect(
        await controller.renameConversation(first, 'Unexpected change'),
        false,
      );
      expect(
        controller.conversations.firstWhere((c) => c.id == first).title,
        'Garden',
      );
      expect(await controller.deleteConversation(first), false);
      expect(controller.conversations, hasLength(2));
      expect(repo.preferences['chat:property'], saved);
      repo.fail = false;
      expect(await controller.openConversation(first), true);
      expect(controller.messages, hasLength(2));
      controller.dispose();
    },
  );
  test(
    'busy navigation is blocked and a cancelled late answer cannot enter the new chat',
    () async {
      final repo = ChatMemoryRepository(),
          started = Completer<void>(),
          answer = Completer<AssistantReply>();
      final chat = make(
        repo,
        assistant: () => FakeAssistant((p, h) {
          started.complete();
          return answer.future;
        }),
      );
      await chat.load();
      final old = chat.activeConversation.id;
      final pending = chat.send('Old question');
      await started.future;
      expect(await chat.newConversation(), false);
      expect(await chat.openConversation(old), false);
      chat.cancel();
      expect(await chat.newConversation(), true);
      final fresh = chat.activeConversation.id;
      answer.complete(const AssistantReply('Late answer', []));
      await pending;
      expect(chat.activeConversation.id, fresh);
      expect(chat.messages, isEmpty);
      expect(
        chat.conversations.firstWhere((c) => c.id == old).messages.single.text,
        'Old question',
      );
      expect(repo.preferences['chat:property'], isNot(contains('Late answer')));
      chat.dispose();
    },
  );
  test(
    'unknown archive versions are preserved and cannot be overwritten by send or new chat',
    () async {
      final repo = ChatMemoryRepository();
      repo.preferences['chat:property'] = '{"version":999,"future":"data"}';
      final chat = make(repo);
      await chat.load();
      expect(chat.error, isNotNull);
      expect(chat.unavailable, true);
      await chat.send('Area?');
      expect(await chat.newConversation(), false);
      expect(
        repo.preferences['chat:property'],
        '{"version":999,"future":"data"}',
      );
      chat.dispose();
    },
  );
  test(
    'conversation migration and multiple resumed chats survive a real SQLite reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lando-conversations-',
      );
      final path = '${directory.path}/lando.db';
      Future<PropertyRepository> open() => PropertyRepository.open(
        databasePath: path,
        factory: databaseFactoryFfi,
      );
      var repo = await open();
      await repo.save(exampleProperty());
      final legacy = [
        ChatMessage(
          role: 'user',
          text: 'Remember my garden',
          created: DateTime.utc(2020),
        ),
      ];
      await repo.setPreference(
        'chat:property',
        jsonEncode(legacy.map((m) => m.toJson()).toList()),
      );
      var chat = make(repo);
      await chat.load();
      final first = chat.activeConversation.id;
      await chat.newConversation();
      await chat.send('A different project');
      final second = chat.activeConversation.id;
      await chat.openConversation(first);
      await chat.send('Continue the garden');
      chat.dispose();
      await repo.db.close();
      repo = await open();
      chat = make(repo);
      await chat.load();
      expect(chat.activeConversation.id, first);
      expect(chat.messages, hasLength(3));
      expect(chat.conversations, hasLength(2));
      await chat.openConversation(second);
      expect(chat.messages.first.text, 'A different project');
      chat.dispose();
      await repo.delete('property');
      expect(await repo.preference('chat:property'), isNull);
      await repo.db.close();
      await directory.delete(recursive: true);
    },
  );
  test(
    'archive repairs a missing active ID by selecting the latest conversation',
    () {
      final a = ChatConversation.empty(), b = ChatConversation.empty();
      b.modified = a.modified.add(const Duration(days: 1));
      final stored = ConversationArchive(
        conversations: [a, b],
        activeId: 'missing',
      );
      expect(
        ConversationArchive.fromStored(jsonEncode(stored.toJson())).activeId,
        b.id,
      );
    },
  );
}
