import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lando/controllers/property_controller.dart';
import 'package:lando/models/chat_conversation.dart';
import 'package:lando/models/chat_message.dart';
import 'package:lando/models/property.dart';
import 'package:lando/models/tag_unit.dart';
import 'package:lando/models/web_research.dart';
import 'package:lando/services/data_backup.dart';
import 'package:lando/services/property_repository.dart';
import 'package:lando/widgets/data_transfer_sheet.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class TestFiles extends BackupFiles {
  Uint8List? selected;
  DataBackup? saved;
  bool saveResult = true;
  @override
  Future<Uint8List?> pick() async => selected;
  @override
  Future<bool> save(DataBackup backup) async {
    saved = backup;
    return saveResult;
  }

  @override
  Future<void> share(DataBackup backup, Rect origin) async {
    saved = backup;
  }
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  sqfliteFfiInit();
  late PropertyRepository repo;
  Property property(String name) => Property(
    id: name,
    name: name,
    points: [],
    latitude: 35,
    longitude: -89,
    created: DateTime.utc(2026),
    modified: DateTime.utc(2026),
    layers: [
      PropertyLayer(
        id: 'area',
        kind: LayerKind.area,
        name: 'Garden',
        imperialTagUnit: TagUnit.squareYards,
        metricTagUnit: TagUnit.squareMeters,
      ),
      PropertyLayer(id: 'path', kind: LayerKind.distance, name: 'Fence'),
    ],
  );
  setUp(() async {
    repo = await PropertyRepository.open(
      databasePath: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
  });
  tearDown(() async => repo.db.close());

  test(
    'restore preserves data but requires new assistant sharing consent',
    () async {
      await repo.setPreference('assistantConsent:v1:openai:web', 'true');
      await repo.setPreference('theme', 'dark');
      final backup = await DataBackup.capture(repo);
      await backup.restore(repo);
      expect(await repo.preference('assistantConsent:v1:openai:web'), isNull);
      expect(await repo.preference('theme'), 'dark');
    },
  );

  Future<DataBackup> populate() async {
    await repo.save(property('Farm'));
    final archive = ConversationArchive.empty();
    archive.active.messages.add(
      ChatMessage(role: 'user', text: 'Fence estimate?'),
    );
    final second = ChatConversation.empty();
    second.messages.add(
      ChatMessage(
        role: 'assistant',
        text: 'Estimate.\n\nDetails: All supporting detail.',
        research: WebResearch(
          checkedAt: DateTime.utc(2026),
          citations: [
            const WebCitation(
              start: 0,
              end: 8,
              url: 'https://example.com/costs',
              title: 'Costs',
            ),
          ],
          searchSuggestions: ['<div>Suggestions</div>'],
        ),
        calculations: [
          const CalculationRecord('area', {'squareMeters': 32}),
        ],
      ),
    );
    archive.conversations.add(second);
    archive.activeId = second.id;
    await repo.setPreference('chat:Farm', jsonEncode(archive.toJson()));
    await repo.setPreference('theme', 'dark');
    await repo.setPreference('queryInternet', 'true');
    await repo.setPreference('aiProvider', 'gemini');
    await repo.setPreference('geminiModel', 'configured-model');
    await repo.setPreference(
      'draft',
      jsonEncode(property('Unfinished draft').toJson()),
    );
    return DataBackup.capture(repo);
  }

  test(
    'portable round trip preserves all tables, unfinished draft, chats and settings',
    () async {
      final original = await populate();
      final bytes = original.encode();
      final imported = DataBackup.decode(bytes);
      expect(imported.properties.length, 1);
      expect(imported.areaCount, 1);
      expect(imported.measurementCount, 1);
      expect(imported.conversationCount, 2);
      expect(imported.hasDraft, true);
      await repo.save(property('Will be replaced'));
      await repo.setPreference('extra', 'will be removed');
      await imported.restore(repo);
      final result = await DataBackup.capture(repo);
      expect(result.properties, original.properties);
      expect(result.preferences, original.preferences);
      expect(await repo.preference('extra'), isNull);
      final controller = PropertyController(repo);
      await controller.reloadAfterRestore();
      expect(controller.property!.name, 'Unfinished draft');
      expect(controller.dirty, true);
      controller.dispose();
    },
  );

  test(
    'invalid, unsupported, duplicate and corrupt files do not modify current data',
    () async {
      final original = await populate();
      final base =
          jsonDecode(utf8.decode(original.encode())) as Map<String, dynamic>;
      final variants = [
        {...base, 'version': 99},
        {
          ...base,
          'properties': [base['properties'][0], base['properties'][0]],
        },
        {
          ...base,
          'properties': [
            {...base['properties'][0], 'latitude': 999},
          ],
        },
        {
          ...base,
          'preferences': {'draft': '{bad json'},
        },
        {
          ...base,
          'preferences': {'chat:Farm': '{"version":999}'},
        },
        {
          ...base,
          'preferences': {'theme': 3},
        },
      ];
      for (final invalid in variants) {
        expect(
          () => DataBackup.decode(utf8.encode(jsonEncode(invalid))),
          throwsFormatException,
        );
      }
      expect(() => DataBackup.decode([0xff]), throwsFormatException);
      expect(
        () => DataBackup.decode(Uint8List(DataBackup.maxBytes + 1)),
        throwsFormatException,
      );
      final after = await DataBackup.capture(repo);
      expect(after.properties, original.properties);
      expect(after.preferences, original.preferences);
    },
  );

  test('failed restore rolls back deletes and all previous inserts', () async {
    final imported = await populate();
    await repo.save(property('Existing'));
    await repo.setPreference('theme', 'light');
    final before = await DataBackup.capture(repo);
    await repo.db.execute(
      "CREATE TRIGGER block_restore BEFORE INSERT ON preferences BEGIN SELECT RAISE(ABORT, 'simulated storage failure'); END",
    );
    await expectLater(
      imported.restore(repo),
      throwsA(isA<DatabaseException>()),
    );
    final after = await DataBackup.capture(repo);
    expect(after.properties, before.properties);
    expect(after.preferences, before.preferences);
  });

  test(
    'empty backup replaces data and clears the controller selection',
    () async {
      final empty = await DataBackup.capture(repo);
      final controller = PropertyController(repo);
      controller.create('Old draft', [], 35, -89, 17);
      await controller.persistDraft();
      await empty.restore(repo);
      await controller.reloadAfterRestore();
      expect(controller.property, isNull);
      expect(controller.dirty, false);
      expect(await repo.preference('draft'), isNull);
      controller.dispose();
    },
  );

  testWidgets(
    'import previews, cancels safely, then replaces only on confirmation',
    (tester) => tester.runAsync(() async {
      final backup = await populate();
      await repo.save(property('Current'));
      final files = TestFiles()..selected = backup.encode();
      bool? restored;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  restored = await showModalBottomSheet<bool>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) =>
                        DataTransferSheet(repository: repo, files: files),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await settle(tester);
      await tester.tap(find.text('Import backup file'));
      await settle(tester);
      expect(find.text('Restore this backup?'), findsOneWidget);
      expect(await repo.list(), hasLength(2));
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(await repo.list(), hasLength(2));
      await tester.tap(find.text('Import backup file'));
      await settle(tester);
      await tester.tap(find.text('Replace & restore'));
      await settle(tester);
      expect(restored, true);
      expect((await repo.list()).single.name, 'Farm');
    }),
  );

  testWidgets(
    'save exports whole snapshot and canceled pick leaves storage alone',
    (tester) => tester.runAsync(() async {
      final original = await populate();
      final files = TestFiles();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DataTransferSheet(repository: repo, files: files),
          ),
        ),
      );
      await tester.tap(find.text('Save backup to Files'));
      await settle(tester);
      expect(files.saved!.preferences, original.preferences);
      expect(find.text('Backup saved.'), findsOneWidget);
      await tester.tap(find.text('Import backup file'));
      await settle(tester);
      expect(find.text('Restore this backup?'), findsNothing);
      expect(
        (await DataBackup.capture(repo)).preferences,
        original.preferences,
      );
    }),
  );
}
