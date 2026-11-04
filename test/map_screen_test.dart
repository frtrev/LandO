import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show GoogleMap;
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:lando/models/property.dart';
import 'package:lando/models/tag_unit.dart';
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
      final original = map.objects.markers.first;
      final coordinates = map.objects.polygons.single.points.toList();
      await tester.tap(find.byTooltip('Lock boundary editing'));
      await tester.pumpAndSettle();
      expect(find.text('Property coordinates locked'), findsOneWidget);
      expect(map.objects.markers.every((m) => !m.draggable), true);
      map.objects.markers.first.onTap!();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      map.objects.markers.first.infoWindow.onTap!();
      original.onDragEnd!(const LatLng(30.002, -98));
      await tester.pumpAndSettle();
      expect(map.objects.polygons.single.points, coordinates);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Add point'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byTooltip('Insert after A'),
        100,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Insert after A',
              ),
            )
            .onPressed,
        isNull,
      );
      final row = find
          .ancestor(of: find.text('A').last, matching: find.byType(ListTile))
          .first;
      tester.widget<ListTile>(row).onTap!();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Unlock boundary editing'));
      await tester.pumpAndSettle();
      expect(find.text('Property coordinates unlocked'), findsOneWidget);
      expect(map.objects.markers.every((m) => m.draggable), true);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Property coordinates unlocked'), findsNothing);
      map.objects.markers.first.onTap!();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Hide boundary panel'));
      await tester.pumpAndSettle();
      expect(find.text('Total area'), findsNothing);
      expect(map.objects.polygons.single.points, hasLength(4));
      await tester.tap(find.text('Boundary'));
      await tester.pumpAndSettle();
      expect(find.text('Total area'), findsOneWidget);
      await tester.tap(find.text('Boundary'));
      await tester.pumpAndSettle();
      expect(find.text('Total area'), findsNothing);
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.text('Total area'), findsOneWidget);
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();

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
  testWidgets(
    'areas and multiple measurement paths can be drawn, saved and reopened',
    (tester) async {
      final map = MapHarness();
      GoogleMapsFlutterPlatform.instance = map;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('flutter.baseflow.com/geolocator'),
            (call) async => 0,
          );
      final repo = MemoryRepository();
      final now = DateTime.now();
      await repo.save(
        Property(
          id: 'layers-test',
          name: 'My land',
          points: [
            const BoundaryPoint(
              id: 'a',
              label: 'A',
              latitude: 30,
              longitude: -98,
            ),
            const BoundaryPoint(
              id: 'b',
              label: 'B',
              latitude: 30,
              longitude: -97.999,
            ),
            const BoundaryPoint(
              id: 'c',
              label: 'C',
              latitude: 30.001,
              longitude: -97.999,
            ),
            const BoundaryPoint(
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
      await tester.binding.setSurfaceSize(const Size(390, 844));
      Future<void> mount() async {
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
      }

      Future<void> animateModal() async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }

      Future<void> nameShape(String name) async {
        await tester.enterText(find.byType(TextField), name);
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(FilledButton, 'Done'),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> tapMap(double lat, double lon) async {
        tester.widget<GoogleMap>(find.byType(GoogleMap)).onTap!(
          LatLng(lat, lon),
        );
        await tester.pumpAndSettle();
      }

      await mount();
      await tester.tap(find.text('Layers'));
      await animateModal();
      await tester.tap(find.text('Add area'));
      await animateModal();
      await nameShape('Garden');
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Save property',
              ),
            )
            .onPressed,
        isNull,
      );
      await tapMap(30.0001, -97.9999);
      await tapMap(30.0001, -97.9997);
      await tapMap(30.0003, -97.9999);
      expect(map.objects.polygons, hasLength(2));
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Save property',
              ),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();
      for (final name in ['Driveway', 'Fence']) {
        await tester.tap(find.text('Measure'));
        await animateModal();
        await nameShape(name);
        await tapMap(30, -98);
        await tapMap(30.0005, -98);
        expect(map.objects.polylines.last.points, hasLength(2));
        await tester.tap(find.widgetWithText(FilledButton, 'Done'));
        await tester.pumpAndSettle();
      }
      expect(map.objects.polylines, hasLength(2));
      await tester.tap(find.byTooltip('Save property'));
      await tester.pumpAndSettle();
      expect(repo.properties['layers-test']!.layers.map((l) => l.name), [
        'Garden',
        'Driveway',
        'Fence',
      ]);
      await tester.pumpWidget(const SizedBox());
      await mount();
      expect(map.objects.polygons, hasLength(2));
      expect(map.objects.polylines, hasLength(2));
      expect(
        map.objects.markers.where(
          (m) => m.markerId.value.startsWith('measurement-label-'),
        ),
        hasLength(3),
      );
      final garden = repo.properties['layers-test']!.layers.first;
      final driveway = repo.properties['layers-test']!.layers[1];
      final gardenTag = map.objects.markers.firstWhere(
        (m) => m.markerId.value == 'measurement-label-${garden.id}',
      );
      final drivewayTag = map.objects.markers.firstWhere(
        (m) => m.markerId.value == 'measurement-label-${driveway.id}',
      );
      gardenTag.onTap!();
      drivewayTag.onTap!();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(garden.tagUnit(metric: false), TagUnit.squareFeet);
      expect(driveway.tagUnit(metric: false), TagUnit.yards);
      expect(
        repo.properties['layers-test']!.layers.last.tagUnit(metric: false),
        TagUnit.feet,
      );
      expect(find.text('Garden'), findsNothing);
      await tester.tap(find.byTooltip('Save property'));
      await tester.pumpAndSettle();
      final saved = Property.fromJson(repo.properties['layers-test']!.toJson());
      expect(saved.layers.first.tagUnit(metric: false), TagUnit.squareFeet);
      expect(saved.layers[1].tagUnit(metric: false), TagUnit.yards);
      await tester.tap(find.byTooltip('Hide area & distance labels'));
      await tester.pumpAndSettle();
      expect(
        map.objects.markers.where(
          (m) => m.markerId.value.startsWith('measurement-label-'),
        ),
        isEmpty,
      );
      expect(map.objects.polygons, hasLength(2));
      expect(map.objects.polylines, hasLength(2));
      await tester.tap(find.byTooltip('Show area & distance labels'));
      await tester.pumpAndSettle();
      expect(
        map.objects.markers.where(
          (m) => m.markerId.value.startsWith('measurement-label-'),
        ),
        hasLength(3),
      );
      await tester.tap(find.text('Layers'));
      await animateModal();
      expect(find.text('Garden'), findsOneWidget);
      expect(find.text('Driveway'), findsOneWidget);
      await tester.tap(find.byTooltip('Hide Garden on map'));
      await animateModal();
      expect(find.byTooltip('Show Garden on map'), findsOneWidget);
      expect(find.text('Areas & measurements'), findsOneWidget);
      expect(map.objects.polygons, hasLength(1));
      expect(map.objects.polylines, hasLength(2));
      expect(
        map.objects.markers.where(
          (m) => m.markerId.value.startsWith('measurement-label-'),
        ),
        hasLength(2),
      );
      await tester.ensureVisible(find.byTooltip('Hide Driveway on map'));
      await animateModal();
      await tester.tap(find.byTooltip('Hide Driveway on map'));
      await animateModal();
      expect(map.objects.polylines, hasLength(1));
      expect(find.byTooltip('Show Garden on map'), findsOneWidget);
      expect(find.byTooltip('Show Driveway on map'), findsOneWidget);
      await tester.tap(find.byTooltip('Show Driveway on map'));
      await animateModal();
      await tester.ensureVisible(find.byTooltip('Show Garden on map'));
      await animateModal();
      await tester.tap(find.byTooltip('Show Garden on map'));
      await animateModal();
      expect(map.objects.polygons, hasLength(2));
      expect(map.objects.polylines, hasLength(2));
      await tester.drag(find.text('Garden'), const Offset(0, -180));
      await animateModal();
      expect(find.text('Fence'), findsOneWidget);
      await tester.ensureVisible(find.text('Driveway'));
      await animateModal();
      await tester.tap(find.text('Driveway'));
      await tester.pumpAndSettle();
      expect(map.objects.markers.where((m) => m.draggable), hasLength(2));
      map.objects.markers.firstWhere((m) => m.draggable).onDragEnd!(
        const LatLng(30.0001, -98),
      );
      await tester.pumpAndSettle();
      expect(find.text('Driveway'), findsOneWidget);
      await tester.binding.setSurfaceSize(const Size(667, 375));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.binding.setSurfaceSize(null);
    },
  );
}
