import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lando/controllers/property_controller.dart';
import 'package:lando/models/property.dart';
import 'package:lando/models/tag_unit.dart';
import 'package:lando/services/property_repository.dart';
import 'package:lando/services/area_transform.dart';

List<BoundaryPoint> boundary() => [
  const BoundaryPoint(id: 'a', label: 'A', latitude: 30, longitude: -98),
  const BoundaryPoint(id: 'b', label: 'B', latitude: 30, longitude: -97.999),
  const BoundaryPoint(
    id: 'c',
    label: 'C',
    latitude: 30.001,
    longitude: -97.999,
  ),
  const BoundaryPoint(id: 'd', label: 'D', latitude: 30.001, longitude: -98),
];
void main() {
  sqfliteFfiInit();
  late Directory directory;
  late PropertyRepository repo;
  late PropertyController controller;
  late String path;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lando-layers-');
    path = '${directory.path}/properties.db';
    repo = await PropertyRepository.open(
      databasePath: path,
      factory: databaseFactoryFfi,
    );
    controller = PropertyController(repo)
      ..create('Pasture', boundary(), 30, -98, 18);
  });
  tearDown(() async {
    controller.dispose();
    await repo.db.close();
    await directory.delete(recursive: true);
  });
  void draw(List<List<double>> coordinates) {
    for (final p in coordinates) {
      controller.addLayerPoint(p[0], p[1]);
    }
  }

  test('legacy property JSON opens with no layers', () {
    final old = controller.property!.toJson()..remove('layers');
    expect(Property.fromJson(old).layers, isEmpty);
  });
  test(
    'layer visibility survives saving and reopening without changing geometry',
    () async {
      final layer = controller.startLayer(LayerKind.distance, 'Fence');
      draw([
        [30, -98],
        [30.001, -98],
      ]);
      final originalPoints = layer.points.map((p) => p.toJson()).toList();
      final originalLength = controller.pathLengths[layer.id];
      final legacy = layer.toJson()..remove('visible');
      expect(PropertyLayer.fromJson(legacy).visible, true);
      controller.toggleLayerVisibility(layer.id);
      expect(layer.visible, false);
      expect(controller.activeLayer, isNull);
      expect(controller.pathLengths[layer.id], originalLength);
      expect(layer.points.map((p) => p.toJson()).toList(), originalPoints);
      await controller.save();
      controller.dispose();
      await repo.db.close();
      repo = await PropertyRepository.open(
        databasePath: path,
        factory: databaseFactoryFfi,
      );
      controller = PropertyController(repo);
      await controller.restore();
      expect(controller.property!.layers.single.visible, false);
      controller.selectLayer(layer.id);
      expect(controller.activeLayer!.visible, true);
      expect(controller.dirty, true);
    },
  );

  test(
    'tag units survive draft recovery, saved reopening and unit-system switches',
    () async {
      final layer = controller.startLayer(LayerKind.distance, 'Fence');
      draw([
        [30, -98],
        [30.001, -98],
      ]);
      final length = controller.pathLengths[layer.id];
      controller.cycleLayerTagUnit(layer.id);
      expect(layer.tagUnit(metric: false), TagUnit.yards);
      controller.property!.metric = true;
      controller.cycleLayerTagUnit(layer.id);
      expect(layer.tagUnit(metric: true), TagUnit.centimeters);
      await controller.persistDraft();
      controller.dispose();
      controller = PropertyController(repo);
      await controller.restore();
      expect(
        controller.property!.layers.single.tagUnit(metric: false),
        TagUnit.yards,
      );
      expect(
        controller.property!.layers.single.tagUnit(metric: true),
        TagUnit.centimeters,
      );
      expect(controller.pathLengths[layer.id], length);
      await controller.save();
      controller.dispose();
      await repo.db.close();
      repo = await PropertyRepository.open(
        databasePath: path,
        factory: databaseFactoryFfi,
      );
      controller = PropertyController(repo);
      await controller.restore();
      final restored = controller.property!.layers.single;
      expect(restored.tagUnit(metric: false), TagUnit.yards);
      expect(restored.tagUnit(metric: true), TagUnit.centimeters);
      expect(controller.dirty, false);
    },
  );

  test(
    'custom area transformations preserve metadata and boundary through drafts and SQLite',
    () async {
      final originalBoundary = controller.property!.points
          .map((p) => p.toJson())
          .toList();
      final layer = controller.startLayer(LayerKind.area, 'Garden');
      draw([
        [30.0001, -97.9999],
        [30.0001, -97.9997],
        [30.0003, -97.9997],
        [30.0003, -97.9999],
      ]);
      controller.cycleLayerTagUnit(layer.id);
      final snapshot = AreaTransform(layer.points, controller.geometry);
      expect(
        controller.replaceAreaPoints(
          layer.id,
          snapshot.apply(scale: 1.5, degrees: 30),
        ),
        true,
      );
      final transformed = layer.points.map((p) => p.toJson()).toList();
      expect(layer.name, 'Garden');
      expect(layer.imperialTagUnit, TagUnit.squareFeet);
      expect(layer.points.map((p) => p.id), snapshot.points.map((p) => p.id));
      final invalid = layer.points
          .map((p) => p.move(999, p.longitude))
          .toList();
      expect(controller.replaceAreaPoints(layer.id, invalid), false);
      expect(layer.points.map((p) => p.toJson()).toList(), transformed);
      await controller.persistDraft();
      controller.dispose();
      controller = PropertyController(repo);
      await controller.restore();
      expect(
        controller.property!.layers.single.points
            .map((p) => p.toJson())
            .toList(),
        transformed,
      );
      expect(
        controller.property!.points.map((p) => p.toJson()).toList(),
        originalBoundary,
      );
      await controller.save();
      controller.dispose();
      await repo.db.close();
      repo = await PropertyRepository.open(
        databasePath: path,
        factory: databaseFactoryFfi,
      );
      controller = PropertyController(repo);
      await controller.restore();
      expect(
        controller.property!.layers.single.points
            .map((p) => p.toJson())
            .toList(),
        transformed,
      );
      expect(
        controller.property!.layers.single.imperialTagUnit,
        TagUnit.squareFeet,
      );
      expect(
        controller.property!.points.map((p) => p.toJson()).toList(),
        originalBoundary,
      );
    },
  );

  test(
    'multiple independent areas and open paths survive SQLite reopen',
    () async {
      final originalArea = controller.result.squareMeters;
      final originalBoundary = controller.property!.points
          .map((p) => p.toJson())
          .toList();
      final garden = controller.startLayer(LayerKind.area, 'Garden');
      draw([
        [30.0001, -97.9999],
        [30.0001, -97.9997],
        [30.0003, -97.9997],
        [30.0003, -97.9999],
      ]);
      final gardenArea = controller.areaResults[garden.id]!.squareMeters!;
      final pond = controller.startLayer(LayerKind.area, 'Pond');
      draw([
        [30.0005, -97.9995],
        [30.0005, -97.9993],
        [30.0007, -97.9995],
      ]);
      final driveway = controller.startLayer(LayerKind.distance, 'Driveway');
      draw([
        [30, -98],
        [30, -97.9998],
        [30.0002, -97.9998],
      ]);
      final pathLength = controller.pathLengths[driveway.id]!;
      expect(
        pathLength,
        lessThan(
          controller.geometry.calculate(driveway.points).perimeterMeters!,
        ),
      );
      controller.startLayer(LayerKind.distance, 'Fence');
      draw([
        [30.0005, -98],
        [30.0008, -98],
      ]);
      expect(controller.result.squareMeters, originalArea);
      expect(
        controller.property!.points.map((p) => p.toJson()).toList(),
        originalBoundary,
      );
      expect(controller.canSave, isTrue);
      await controller.save();
      final id = controller.property!.id;
      controller.dispose();
      await repo.db.close();
      repo = await PropertyRepository.open(
        databasePath: path,
        factory: databaseFactoryFfi,
      );
      controller = PropertyController(repo);
      await controller.restore();
      expect(controller.property!.id, id);
      expect(controller.property!.layers.map((l) => l.name), [
        'Garden',
        'Pond',
        'Driveway',
        'Fence',
      ]);
      expect(controller.areaResults[garden.id]!.squareMeters, gardenArea);
      expect(controller.pathLengths[driveway.id], pathLength);
      expect(controller.activeLayer, isNull);
      controller.selectLayer(garden.id);
      controller.insertLayerPoint(garden.id, 1);
      expect(controller.activeLayer!.points.map((p) => p.label), [
        'A',
        'B',
        'E',
        'C',
        'D',
      ]);
      expect(
        controller.areaResults[garden.id]!.squareMeters,
        closeTo(gardenArea, .002),
      );
      controller.renameLayer(pond.id, 'Wildlife pond');
      controller.deleteLayer(driveway.id);
      expect(controller.dirty, isTrue);
      await controller.save();
      final saved = (await repo.list()).single;
      expect(saved.layers.map((l) => l.name), [
        'Garden',
        'Wildlife pond',
        'Fence',
      ]);
      expect(saved.layers.first.points.map((p) => p.label), [
        'A',
        'B',
        'E',
        'C',
        'D',
      ]);
      controller.create('Another property', boundary(), 30, -98, 18);
      expect(controller.property!.layers, isEmpty);
    },
  );
  test(
    'incomplete and crossing layers cannot overwrite a valid property; drafts recover them',
    () async {
      await controller.save();
      final layer = controller.startLayer(LayerKind.area, 'Work in progress');
      draw([
        [30, -98],
        [30.001, -97.999],
        [30, -97.999],
        [30.001, -98],
      ]);
      expect(controller.areaResults[layer.id]!.valid, isFalse);
      expect(controller.canSave, isFalse);
      await controller.save();
      expect((await repo.list()).single.layers, isEmpty);
      await controller.persistDraft();
      controller.dispose();
      controller = PropertyController(repo);
      await controller.restore();
      expect(controller.dirty, isTrue);
      expect(controller.property!.layers.single.name, 'Work in progress');
      expect(controller.areaResults[layer.id]!.squareMeters, isNull);
      controller.selectLayer(layer.id);
      controller.clearLayer();
      expect(controller.canSave, isFalse);
      draw([
        [30, -98],
        [30, -97.999],
        [30.001, -98],
      ]);
      expect(controller.canSave, isTrue);
      controller.undoLayerPoint();
      expect(controller.canSave, isFalse);
      controller.deleteLayer(layer.id);
      expect(controller.activeLayer, isNull);
      expect(controller.canSave, isTrue);
    },
  );
  test(
    'path coordinates can be edited, split, deleted and validated without closing the path',
    () {
      final layer = controller.startLayer(LayerKind.distance, 'Fence');
      draw([
        [30, -98],
        [30, -97.999],
      ]);
      final length = controller.pathLengths[layer.id]!;
      controller.insertLayerPoint(layer.id, 0);
      expect(layer.points.map((p) => p.label), ['A', 'C', 'B']);
      expect(controller.pathLengths[layer.id], closeTo(length, .001));
      controller.insertLayerPoint(layer.id, 2);
      expect(layer.points, hasLength(3)); // No closing edge on an open path.
      controller.removeLayerPoint(layer.id, layer.points[1].id);
      controller.moveLayerPoint(layer.id, layer.points.last.id, 30, -98);
      expect(controller.canSave, isFalse);
      expect(controller.pathLengths.containsKey(layer.id), isFalse);
      controller.moveLayerPoint(layer.id, layer.points.last.id, 30.001, -98);
      expect(controller.canSave, isTrue);
      expect(controller.result.squareMeters, isNotNull);
    },
  );
}
