import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:lando/models/property.dart';
import 'package:lando/screens/map_screen.dart';
import 'package:lando/services/property_repository.dart';
import 'package:sqflite/sqflite.dart';

/// UI harness only; real map gestures/tiles require device acceptance.
class MapHarness extends GoogleMapsFlutterPlatform {
  MapObjects objects = const MapObjects();
  @override
  Widget buildViewWithConfiguration(
    int id,
    PlatformViewCreatedCallback onCreated, {
    required MapWidgetConfiguration widgetConfiguration,
    MapConfiguration mapConfiguration = const MapConfiguration(),
    MapObjects mapObjects = const MapObjects(),
  }) {
    objects = mapObjects;
    return const ColoredBox(color: Color(0xff243d30));
  }
}

class MemoryRepository implements PropertyRepository {
  final Map<String, String> preferences = {};
  final Map<String, Property> properties = {};
  @override
  Database get db => throw UnimplementedError();
  @override
  Future<List<Property>> list() async => properties.values.toList();
  @override
  Future<String?> preference(String key) async => preferences[key];
  @override
  Future<void> setPreference(String key, String value) async {
    preferences[key] = value;
  }

  @override
  Future<void> save(Property property) async {
    properties[property.id] = property;
    preferences['lastProperty'] = property.id;
  }

  @override
  Future<void> delete(String id) async {
    properties.remove(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'restored property shows measurements, ordered coordinate insertion, and compact landscape details',
    (tester) async {
      final map = MapHarness();
      GoogleMapsFlutterPlatform.instance = map;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('flutter.baseflow.com/geolocator'),
            (call) async => 0,
          );
      final repo = MemoryRepository();
      await tester.runAsync(() async {
        final now = DateTime.now();
        await repo.save(
          Property(
            id: 'test',
            name: 'Test pasture',
            points: [
              BoundaryPoint(id: 'a', label: 'A', latitude: 30, longitude: -98),
              BoundaryPoint(
                id: 'b',
                label: 'B',
                latitude: 30,
                longitude: -97.999,
              ),
              BoundaryPoint(
                id: 'c',
                label: 'C',
                latitude: 30.001,
                longitude: -97.999,
              ),
              BoundaryPoint(
                id: 'd',
                label: 'D',
                latitude: 30.001,
                longitude: -98,
              ),
            ],
            latitude: 30,
            longitude: -98,
            created: now,
            modified: now,
          ),
        );
      });
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(
        MaterialApp(
          home: MapScreen(
            repository: repo,
            themeMode: ThemeMode.light,
            onTheme: (_) {},
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Total area'), findsOneWidget);
      expect(map.objects.markers, hasLength(4));
      expect(map.objects.polygons.single.points, hasLength(4));
      await tester.tap(find.text('Add point'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text('B → C'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(map.objects.markers, hasLength(5));
      expect(find.text('Unsaved'), findsOneWidget);
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.text('5 boundary points'), findsOneWidget);
      await tester.binding.setSurfaceSize(const Size(667, 375));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Map & preferences'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.binding.setSurfaceSize(null);
    },
  );
}
