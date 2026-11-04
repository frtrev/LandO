// No API calls or credentials. Uses isolated databases and a real backup file.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lando/controllers/property_controller.dart';
import 'package:lando/models/property.dart';
import 'package:lando/services/data_backup.dart';
import 'package:lando/services/property_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('backup file restores into a fresh native mobile database', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'lando-backup-test-',
    );
    final source = await PropertyRepository.open(
      databasePath: '${directory.path}/source.db',
    );
    final target = await PropertyRepository.open(
      databasePath: '${directory.path}/target.db',
    );
    final now = DateTime.now().toUtc();
    try {
      await source.save(
        Property(
          id: 'test-property',
          name: 'Backup test',
          points: [],
          latitude: 35,
          longitude: -89,
          created: now,
          modified: now,
          layers: [
            PropertyLayer(id: 'area', kind: LayerKind.area, name: 'Garden'),
            PropertyLayer(
              id: 'distance',
              kind: LayerKind.distance,
              name: 'Fence',
            ),
          ],
        ),
      );
      await source.setPreference('theme', 'dark');
      final before = await DataBackup.capture(source);
      final file = File('${directory.path}/${before.fileName}');
      await file.writeAsBytes(before.encode(), flush: true);
      final backup = DataBackup.decode(await file.readAsBytes());
      await backup.restore(target);
      await target.db.close();
      final reopened = await PropertyRepository.open(
        databasePath: '${directory.path}/target.db',
      );
      try {
        final after = await DataBackup.capture(reopened);
        expect(after.properties, before.properties);
        expect(after.preferences, before.preferences);
        final controller = PropertyController(reopened);
        await controller.restore();
        expect(controller.property!.name, 'Backup test');
        expect(controller.property!.layers.length, 2);
        controller.dispose();
      } finally {
        await reopened.db.close();
      }
    } finally {
      await source.db.close();
      if (target.db.isOpen) await target.db.close();
      await directory.delete(recursive: true);
    }
  });
}
