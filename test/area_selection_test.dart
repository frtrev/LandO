import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'
    show GoogleMap, LatLng;
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:lando/models/property.dart';
import 'package:lando/screens/map_screen.dart';
import 'package:lando/services/geometry_service.dart';
import 'map_screen_test.dart' show MapHarness, MemoryRepository;
import 'support/assistant_fixtures.dart' show exampleProperty;

void main() {
  testWidgets(
    'area selection swaps menus, previews/cancels resizing, rotates and exits on map tap',
    (tester) async {
      final map = MapHarness();
      GoogleMapsFlutterPlatform.instance = map;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('flutter.baseflow.com/geolocator'),
            (call) async => 0,
          );
      final repo = MemoryRepository();
      await repo.save(exampleProperty());
      final originalBoundary = repo.properties.values.single.points
          .map((p) => p.toJson())
          .toList();
      final originalPoints = repo.properties.values.single.layers.first.points
          .map((p) => p.toJson())
          .toList();
      final geometry = GeometryService();
      double area() => geometry
          .calculate(
            map.objects.polygons
                .firstWhere((p) => p.polygonId.value == 'garden')
                .points
                .asMap()
                .entries
                .map(
                  (p) => BoundaryPoint(
                    id: '${p.key}',
                    label: '',
                    latitude: p.value.latitude,
                    longitude: p.value.longitude,
                  ),
                )
                .toList(),
          )
          .squareMeters!;
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
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      final originalArea = area();
      map.objects.polygons
          .firstWhere((p) => p.polygonId.value == 'garden')
          .onTap!();
      await tester.pumpAndSettle();
      expect(find.text('Resize'), findsOneWidget);
      expect(find.text('Rotate'), findsOneWidget);
      expect(find.text('Properties'), findsNothing);
      await tester.tap(find.text('Resize'));
      await tester.pumpAndSettle();
      tester.widget<Slider>(find.byType(Slider)).onChanged!(2);
      await tester.pumpAndSettle();
      expect(area(), closeTo(originalArea * 4, .02));
      await tester.ensureVisible(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        repo.properties.values.single.layers.first.points
            .map((p) => p.toJson())
            .toList(),
        originalPoints,
      );
      await tester.tap(find.text('Rotate'));
      await tester.pumpAndSettle();
      tester.widget<Slider>(find.byType(Slider)).onChanged!(90);
      await tester.pumpAndSettle();
      expect(area(), closeTo(originalArea, .01));
      await tester.ensureVisible(find.text('Apply'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      tester.widget<GoogleMap>(find.byType(GoogleMap)).onTap!(
        const LatLng(30.003, -98),
      );
      await tester.pumpAndSettle();
      expect(find.text('Properties'), findsOneWidget);
      expect(find.text('Resize'), findsNothing);
      expect(
        repo.properties.values.single.points.map((p) => p.toJson()).toList(),
        originalBoundary,
      );
      expect(repo.properties.values.single.layers.first.points.length, 4);
      await tester.tap(find.byTooltip('Save property'));
      await tester.pumpAndSettle();
      expect(
        repo.properties.values.single.layers.first.points
            .map((p) => p.toJson())
            .toList(),
        isNot(originalPoints),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.binding.setSurfaceSize(null);
    },
  );
}
