// Run on an isolated iOS simulator. Uses only the synthetic in-memory demo.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lando/screens/map_screen.dart';
import 'package:lando/services/assistant/api_key_store.dart';
import 'package:lando/services/assistant/assistant_provider.dart';
import 'package:lando/services/data_backup.dart';
import 'package:lando/services/property_repository.dart';
import 'package:lando/widgets/assistant/assistant_sharing_consent.dart';
import '../tools/store_preview.dart' as preview;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('iOS map, layers, native notices, Keychain and SQLite backup', (
    tester,
  ) async {
    expect(Platform.isIOS, true);
    await tester.runAsync(preview.main);
    Future<void> frames() async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await frames();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 8)),
    );
    await frames();
    expect(find.text('Demo pasture'), findsWidgets);
    final map = tester.widget<MapScreen>(find.byType(MapScreen));
    await tester.runAsync(() async {
      final repo = map.repository;
      final backup = DataBackup.decode(
        (await DataBackup.capture(repo)).encode(),
      );
      expect(backup.properties.length, 1);
      expect(backup.areaCount, 1);
      expect(backup.measurementCount, 1);
      final restoreDir = await Directory.systemTemp.createTemp(
        'lando-restore-test-',
      );
      final restored = await PropertyRepository.open(
        databasePath: '${restoreDir.path}/restore.db',
      );
      await backup.restore(restored);
      expect((await restored.list()).single.name, 'Demo pasture');
      await restored.db.close();
      await restoreDir.delete(recursive: true);
      final keys = SecureApiKeyStore();
      // Temporary simulator only; never substitute real provider credentials.
      await keys.save('lando-smoke-placeholder');
      expect(await keys.read(), 'lando-smoke-placeholder');
      await keys.delete();
      expect(await keys.read(), isNull);
      final notices = await const MethodChannel(
        'lando/config',
      ).invokeMethod<String>('legalNotices');
      expect(notices, contains('Google Maps'));
      expect(notices, contains('Google Places'));
      expect(notices!.length, greaterThan(1000));
    });

    Future<void> snapshot(String name) async {
      await tester.runAsync(() async {
        await binding.takeScreenshot(name);
      });
    }

    await snapshot('01-property-map');
    await tester.tap(find.text('Layers').last);
    await frames();
    expect(find.text('Garden'), findsWidgets);
    expect(find.text('Driveway'), findsWidgets);
    await snapshot('02-saved-layers');
    Navigator.of(tester.element(find.text('Garden').last)).pop();
    await frames();
    await tester.tap(find.byTooltip('Settings'));
    await frames();
    await tester.ensureVisible(find.text('Privacy & support'));
    await tester.tap(find.text('Privacy & support'));
    await frames();
    expect(find.textContaining('LandO Privacy Policy'), findsOneWidget);
    await tester.ensureVisible(find.text('Google Maps & Places legal notices'));
    await tester.tap(find.text('Google Maps & Places legal notices'));
    await frames();
    expect(find.textContaining('Google Maps\n'), findsOneWidget);
    await tester.pageBack();
    await frames();
    await tester.pageBack();
    await frames();
    Navigator.of(tester.element(find.text('Map & preferences'))).pop();
    await frames();

    final context = tester.element(find.byType(MapScreen));
    final permission = AssistantSharingConsent.request(
      context,
      map.repository,
      AssistantProvider.gemini,
      true,
    );
    await frames();
    expect(find.textContaining('Google (Gemini API)'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await frames();
    expect(await permission, false);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
