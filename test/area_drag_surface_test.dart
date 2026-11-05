import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:lando/models/property.dart';
import 'package:lando/widgets/area_drag_surface.dart';

void main() {
  testWidgets(
    'hold inside an area drags, outside and quick pans do not claim it',
    (tester) async {
      final starts = <String>[];
      final moves = <LatLng>[];
      var ends = 0;
      var outsideTaps = 0;
      var cancels = 0;
      final area = PropertyLayer(
        id: 'garden',
        kind: LayerKind.area,
        name: 'Garden',
        points: [
          const BoundaryPoint(
            id: 'a',
            label: 'A',
            latitude: .05,
            longitude: .05,
          ),
          const BoundaryPoint(
            id: 'b',
            label: 'B',
            latitude: .05,
            longitude: .25,
          ),
          const BoundaryPoint(
            id: 'c',
            label: 'C',
            latitude: .25,
            longitude: .25,
          ),
          const BoundaryPoint(
            id: 'd',
            label: 'D',
            latitude: .25,
            longitude: .05,
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AreaDragSurface(
              areas: [area],
              enabled: true,
              hasSelection: true,
              onTapOutside: () => outsideTaps++,
              project: (p) async =>
                  Offset(p.longitude * 1000, p.latitude * 1000),
              unproject: (p) async => LatLng(p.dy / 1000, p.dx / 1000),
              onStart: starts.add,
              onMove: (_, from, to) => moves.add(to),
              onEnd: () => ends++,
              onCancel: () => cancels++,
              child: const SizedBox.expand(
                child: ColoredBox(color: Colors.green),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(350, 350));
      await tester.pumpAndSettle();
      expect(outsideTaps, 1);
      await tester.dragFrom(const Offset(100, 100), const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(starts, isEmpty);
      final outside = await tester.startGesture(const Offset(350, 100));
      await tester.pump(const Duration(milliseconds: 600));
      await outside.moveBy(const Offset(20, 0));
      await outside.up();
      await tester.pumpAndSettle();
      expect(starts, isEmpty);
      final inside = await tester.startGesture(const Offset(100, 100));
      await tester.pump(const Duration(milliseconds: 600));
      expect(starts, ['garden']);
      await inside.moveBy(const Offset(30, 20));
      await tester.pump();
      await inside.up();
      await tester.pumpAndSettle();
      expect(moves.last.latitude, .12);
      expect(moves.last.longitude, .13);
      expect(ends, 1);
      final canceled = await tester.startGesture(const Offset(100, 100));
      await tester.pump(const Duration(milliseconds: 600));
      await canceled.cancel();
      await tester.pumpAndSettle();
      expect(cancels, 1);
      expect(ends, 1);
    },
  );
}
