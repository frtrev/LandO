import 'package:flutter_test/flutter_test.dart';
import 'package:geobase/geobase.dart';
import 'package:lando/models/property.dart';
import 'package:lando/services/area_transform.dart';
import 'package:lando/services/geometry_service.dart';

List<BoundaryPoint> rectangle({double lon = -98}) => [
  BoundaryPoint(id: 'a', label: 'A', latitude: 30, longitude: lon),
  BoundaryPoint(id: 'b', label: 'B', latitude: 30, longitude: lon + .001),
  BoundaryPoint(id: 'c', label: 'C', latitude: 30.002, longitude: lon + .001),
  BoundaryPoint(id: 'd', label: 'D', latitude: 30.002, longitude: lon),
];
void main() {
  final geometry = GeometryService();
  test(
    'resize uses immutable baseline, scales area by scale squared and retains IDs',
    () {
      final points = rectangle(),
          transform = AreaTransform(rectangle(), geometry);
      final area = geometry.calculate(points).squareMeters!;
      expect(
        geometry.calculate(transform.apply(scale: 2)).squareMeters!,
        closeTo(area * 4, .02),
      );
      transform.apply(scale: 3);
      expect(
        geometry.calculate(transform.apply(scale: .5)).squareMeters!,
        closeTo(area * .25, .01),
      );
      expect(
        transform.apply().map((p) => p.toJson()),
        points.map((p) => p.toJson()),
      );
      expect(transform.apply(scale: 2).map((p) => p.id), ['a', 'b', 'c', 'd']);
      expect(transform.apply(scale: 2).map((p) => p.label), [
        'A',
        'B',
        'C',
        'D',
      ]);
    },
  );
  test(
    'rotation preserves area and side lengths and a full turn restores coordinates',
    () {
      final points = rectangle(),
          transform = AreaTransform(rectangle(), geometry);
      final before = geometry.calculate(points),
          after = geometry.calculate(transform.apply(degrees: 90));
      expect(after.valid, true);
      expect(after.squareMeters!, closeTo(before.squareMeters!, .01));
      for (var i = 0; i < before.segments.length; i++) {
        expect(after.segments[i], closeTo(before.segments[i], .001));
      }
      final full = transform.apply(degrees: 360);
      for (var i = 0; i < points.length; i++) {
        expect(geometry.distance(points[i], full[i]), lessThan(.001));
      }
    },
  );
  test(
    'drag translates from the held point without collapsing or moving the source',
    () {
      final points = rectangle(),
          transform = AreaTransform(rectangle(), geometry);
      final moved = transform.drag(
        const Geographic(lat: 30.001, lon: -97.9995),
        const Geographic(lat: 30.011, lon: -97.9895),
      );
      final before = geometry.calculate(points),
          after = geometry.calculate(moved);
      expect(after.valid, true);
      expect(after.center!.lat, closeTo(30.011, .000001));
      expect(after.center!.lon, closeTo(-97.9895, .000001));
      expect(after.squareMeters!, closeTo(before.squareMeters!, .02));
      expect(
        transform.points.map((p) => p.toJson()),
        points.map((p) => p.toJson()),
      );
    },
  );
  test('rotation and translation handle areas crossing the date line', () {
    final points = rectangle(lon: 179.9995)
        .map(
          (p) => p.move(
            p.latitude,
            p.longitude > 180 ? p.longitude - 360 : p.longitude,
          ),
        )
        .toList();
    final transform = AreaTransform(points, geometry);
    expect(geometry.calculate(transform.apply(degrees: 80)).valid, true);
    expect(
      geometry
          .calculate(
            transform.apply(
              target: const Geographic(lat: 30.002, lon: -179.99),
            ),
          )
          .valid,
      true,
    );
  });
}
