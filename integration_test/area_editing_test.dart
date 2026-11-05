// Native map gesture verification. Uses synthetic in-memory data; no AI calls.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lando/models/property.dart';
import 'package:lando/screens/map_screen.dart';
import 'package:lando/services/geometry_service.dart';
import 'package:lando/widgets/area_drag_surface.dart';
import '../test/map_screen_test.dart' show MemoryRepository;
import '../test/support/assistant_fixtures.dart' show exampleProperty;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native hold and drag moves a custom area, rotation and resize work',
    (tester) async {
      final repo = MemoryRepository();
      final property = exampleProperty();
      property.latitude = 30.0005;
      property.longitude = -97.9995;
      property.zoom = 18;
      property.layers.first.points = [
        const BoundaryPoint(
          id: 'a1',
          label: 'A',
          latitude: 30.0003,
          longitude: -97.9998,
        ),
        const BoundaryPoint(
          id: 'b1',
          label: 'B',
          latitude: 30.0003,
          longitude: -97.9992,
        ),
        const BoundaryPoint(
          id: 'c1',
          label: 'C',
          latitude: 30.0007,
          longitude: -97.9992,
        ),
        const BoundaryPoint(
          id: 'd1',
          label: 'D',
          latitude: 30.0007,
          longitude: -97.9998,
        ),
      ];
      await repo.save(property);
      final geometry = GeometryService();
      final before = geometry.calculate(property.layers.first.points);
      final boundary = property.points.map((p) => p.toJson()).toList();
      await tester.pumpWidget(
        MaterialApp(
          home: MapScreen(
            repository: repo,
            themeMode: ThemeMode.light,
            onTheme: (_) {},
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      final surface = tester.widget<AreaDragSurface>(
        find.byType(AreaDragSurface),
      );
      await tester
          .state<AreaDragSurfaceState>(find.byType(AreaDragSurface))
          .refreshProjection();
      final point = await surface.project(const LatLng(30.0005, -97.9995));
      final offset = tester.getTopLeft(find.byType(AreaDragSurface));
      final gesture = await tester.startGesture(offset + point);
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Resize'), findsOneWidget);
      for (var i = 1; i <= 5; i++) {
        await gesture.moveTo(offset + point + Offset(i * 8, -i * 5));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await gesture.up();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final after = geometry.calculate(property.layers.first.points);
      expect(after.valid, true);
      expect(after.center!.lat, isNot(closeTo(before.center!.lat, .00001)));
      expect(after.squareMeters!, closeTo(before.squareMeters!, .03));
      expect(property.points.map((p) => p.toJson()).toList(), boundary);
      await tester.tap(find.text('Rotate'));
      await tester.pumpAndSettle();
      tester.widget<Slider>(find.byType(Slider)).onChanged!(45);
      await tester.pumpAndSettle();
      expect(find.text('Rotate: 45°'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resize'));
      await tester.pumpAndSettle();
      tester.widget<Slider>(find.byType(Slider)).onChanged!(1.5);
      await tester.pumpAndSettle();
      expect(
        geometry.calculate(property.layers.first.points).squareMeters!,
        closeTo(before.squareMeters! * 2.25, .05),
      );
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      await tester
          .state<AreaDragSurfaceState>(find.byType(AreaDragSurface))
          .refreshProjection();
      final outside = await surface.project(const LatLng(30.00095, -97.99995));
      await tester.tapAt(offset + outside);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Properties'), findsOneWidget);
      expect(find.text('Resize'), findsNothing);
    },
  );
}
