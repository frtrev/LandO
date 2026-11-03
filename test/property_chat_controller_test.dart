import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:lando/controllers/property_chat_controller.dart';
import 'package:lando/models/chat_message.dart';
import 'package:lando/models/property.dart';
import 'package:lando/services/assistant/openai_assistant.dart';
import 'package:lando/services/assistant/property_tools.dart';
import 'support/assistant_fixtures.dart';

class FakeAssistant implements LandoAssistant {
  final Future<AssistantReply> Function(Property, List<ChatMessage>) answer;
  bool disposed = false;
  FakeAssistant(this.answer);
  @override
  Future<AssistantReply> ask({
    required Property property,
    required List<ChatMessage> history,
    required String apiKey,
    required String model,
    void Function(CalculationRecord)? onCalculation,
  }) => answer(property, history);
  @override
  void dispose() {
    disposed = true;
  }
}

void main() {
  test(
    'no key makes no API request; saved histories are per property and never contain credentials',
    () async {
      final repo = ChatMemoryRepository(), key = MemoryKeyStore();
      final property = exampleProperty();
      var calls = 0;
      PropertyChatController make() => PropertyChatController(
        propertyId: property.id,
        currentProperty: () => property,
        repository: repo,
        keyStore: key,
        createAssistant: () => FakeAssistant((p, h) async {
          calls++;
          return AssistantReply('Your property is a planning estimate.', [
            CalculationRecord(
              'get_property_area',
              PropertyTools(p).execute('get_property_area', {}),
            ),
          ]);
        }),
      );
      var chat = make();
      await chat.load();
      await chat.send('How many acres?');
      expect(calls, 0);
      expect(chat.configured, false);
      expect(chat.error, contains('API key'));
      await key.save('sk-private-test');
      await chat.reloadConfiguration();
      await chat.send('How many acres?');
      expect(calls, 1);
      expect(chat.messages, hasLength(2));
      chat.dispose();
      chat = make();
      await chat.load();
      expect(chat.messages, hasLength(2));
      expect(
        chat.messages.last.calculations.single.data['area_acres'],
        greaterThan(0),
      );
      expect(repo.preferences.toString(), isNot(contains('sk-private-test')));
      final other = PropertyChatController(
        propertyId: 'other',
        currentProperty: () => exampleProperty(id: 'other'),
        repository: repo,
        keyStore: key,
      );
      await other.load();
      expect(other.messages, isEmpty);
      other.dispose();
      await chat.clearHistory();
      final archive = jsonDecode(
        (await repo.preference('chat:${property.id}'))!,
      );
      expect(archive['version'], 2);
      expect(archive['conversations'].single['messages'], isEmpty);
      chat.dispose();
    },
  );
  test(
    'follow-ups use fresh property geometry and failures can retry without duplicating the question',
    () async {
      final repo = ChatMemoryRepository(), key = MemoryKeyStore('sk-test');
      final property = exampleProperty();
      final seen = <Property>[];
      var fail = true;
      final chat = PropertyChatController(
        propertyId: property.id,
        currentProperty: () => property,
        repository: repo,
        keyStore: key,
        createAssistant: () => FakeAssistant((p, h) async {
          seen.add(p);
          if (fail) {
            throw const AssistantException('Network failed');
          }
          return const AssistantReply('Done', []);
        }),
      );
      await chat.load();
      await chat.send('Area?');
      expect(chat.messages, hasLength(1));
      expect(chat.retryQuestion, 'Area?');
      fail = false;
      property.name = 'Renamed';
      property.points[0] = property.points[0].move(29.9999, -98);
      await chat.send(chat.retryQuestion!, retry: true);
      expect(chat.messages, hasLength(2));
      expect(seen.last.name, 'Renamed');
      expect(seen.first.points[0].latitude, 30);
      expect(seen.last.points[0].latitude, 29.9999);
      chat.dispose();
    },
  );
  test(
    'cancelled requests cannot append a late answer or overwrite history',
    () async {
      final repo = ChatMemoryRepository(),
          key = MemoryKeyStore('sk-test'),
          property = exampleProperty();
      final completer = Completer<AssistantReply>(),
          started = Completer<void>();
      final fake = FakeAssistant((p, h) {
        started.complete();
        return completer.future;
      });
      final chat = PropertyChatController(
        propertyId: property.id,
        currentProperty: () => property,
        repository: repo,
        keyStore: key,
        createAssistant: () => fake,
      );
      await chat.load();
      final pending = chat.send('Area?');
      await started.future;
      chat.cancel();
      expect(fake.disposed, true);
      expect(chat.busy, false);
      completer.complete(const AssistantReply('Late answer', []));
      await pending;
      expect(chat.messages, hasLength(1));
      expect(repo.preferences.values.join(), isNot(contains('Late answer')));
      chat.dispose();
    },
  );
}
