import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lando/controllers/property_controller.dart';
import 'package:lando/models/property.dart';
import 'package:lando/services/property_repository.dart';

void main() {
  sqfliteFfiInit();
  test(
    'saved properties, ordered edits, preferences and drafts survive reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp('lando-test-');
      final path = '${directory.path}/properties.db';
      Future<PropertyRepository> open() => PropertyRepository.open(
        databasePath: path,
        factory: databaseFactoryFfi,
      );
      var repo = await open();
      var controller = PropertyController(repo);
      final coords = [
        [30.0, -98.0],
        [30.0, -97.999],
        [30.001, -97.999],
        [30.001, -98.0],
      ];
      final points = List.generate(
        4,
        (i) => BoundaryPoint(
          id: newId(),
          label: pointLabel(i),
          latitude: coords[i][0],
          longitude: coords[i][1],
        ),
      );
      controller.create('North pasture', points, 30, -98, 18);
      controller.insertAfter(1);
      controller.property!.metric = true;
      controller.property!.description = 'Fence planning';
      controller.property!.bearing = 32;
      await controller.save();
      final firstId = controller.property!.id;
      expect(controller.dirty, isFalse);
      controller.property!.name = 'Unsaved rename';
      controller.changed();
      await controller.persistDraft();
      controller.dispose();
      await repo.db.close();
      repo = await open();
      controller = PropertyController(repo);
      await controller.restore();
      expect(controller.dirty, isTrue);
      expect(controller.property!.name, 'Unsaved rename');
      expect((await repo.list()).single.name, 'North pasture');
      await controller.discardDraft();
      await controller.open((await repo.list()).single);
      expect(controller.property!.points.map((p) => p.label), [
        'A',
        'B',
        'E',
        'C',
        'D',
      ]);
      expect(controller.property!.metric, isTrue);
      expect(controller.property!.bearing, 32);
      expect(controller.property!.description, 'Fence planning');
      controller.remove(controller.property!.points[2].id);
      controller.remove(controller.property!.points[2].id);
      controller.remove(controller.property!.points[0].id);
      expect(controller.property!.points.length, 3);
      await controller.discardDraft();
      controller.create('South pasture', List.from(points), 30, -98, 17);
      await controller.save();
      expect(await repo.list(), hasLength(2));
      await repo.delete(firstId);
      expect(await repo.list(), hasLength(1));
      controller.dispose();
      await repo.db.close();
      await directory.delete(recursive: true);
    },
  );
}
