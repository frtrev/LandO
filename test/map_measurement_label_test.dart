import 'package:flutter_test/flutter_test.dart';
import 'package:lando/models/property.dart';
import 'package:lando/services/geometry_service.dart';
import 'package:lando/services/map_measurement_label.dart';

List<BoundaryPoint> points(List<List<double>> coords) => [
  for (var i = 0; i < coords.length; i++)
    BoundaryPoint(
      id: '$i',
      label: '$i',
      latitude: coords[i][0],
      longitude: coords[i][1],
    ),
];
void main() {
  final geometry = GeometryService();
  test('concave area badge sits inside polygon and respects units', () {
    // U-shaped polygon: arithmetic center lies in the empty central notch.
    final layer = PropertyLayer(
      id: 'garden',
      kind: LayerKind.area,
      name: 'Garden',
      points: points([
        [30, -98],
        [30, -97.994],
        [30.006, -97.994],
        [30.006, -97.996],
        [30.002, -97.996],
        [30.002, -97.998],
        [30.006, -97.998],
        [30.006, -98],
      ]),
    );
    final result = geometry.calculate(layer.points);
    expect(result.valid, true);
    final badge = MapMeasurementLabel.forLayer(
      layer,
      metric: false,
      geometry: geometry,
      areaResult: result,
    )!;
    expect(badge.latitude, closeTo(30.003, .000001));
    expect(badge.longitude < -97.998 || badge.longitude > -97.996, true);
    expect(badge.value, '${result.acres!.toStringAsFixed(3)} acres');
    expect(
      MapMeasurementLabel.forLayer(
        layer,
        metric: true,
        geometry: geometry,
        areaResult: result,
      )!.value,
      endsWith(' ha'),
    );
  });
  test('path badge uses half the full geodesic path, updates after edits', () {
    final layer = PropertyLayer(
      id: 'fence',
      kind: LayerKind.distance,
      name: 'Fence',
      points: points([
        [30, -98],
        [30.001, -98],
        [30.004, -98],
      ]),
    );
    final distance = geometry.pathLength(layer.points);
    final badge = MapMeasurementLabel.forLayer(
      layer,
      metric: false,
      geometry: geometry,
      distance: distance,
    )!;
    expect(badge.latitude, closeTo(30.002, .000001));
    expect(badge.longitude, closeTo(-98, .000001));
    expect(badge.value, '${(distance / .3048).toStringAsFixed(1)} ft');
    layer.points[2] = layer.points[2].move(30.006, -98);
    final changed = MapMeasurementLabel.forLayer(
      layer,
      metric: true,
      geometry: geometry,
      distance: geometry.pathLength(layer.points),
    )!;
    expect(changed.latitude, closeTo(30.003, .000001));
    expect(changed.value, endsWith(' m'));
    expect(changed.iconKey, isNot(badge.iconKey));
  });
  test('invalid or unfinished shapes do not show numeric badges', () {
    final area = PropertyLayer(id: 'a', kind: LayerKind.area, name: 'Area');
    final line = PropertyLayer(id: 'b', kind: LayerKind.distance, name: 'Line');
    expect(
      MapMeasurementLabel.forLayer(
        area,
        metric: false,
        geometry: geometry,
        areaResult: geometry.calculate([]),
      ),
      isNull,
    );
    expect(
      MapMeasurementLabel.forLayer(line, metric: false, geometry: geometry),
      isNull,
    );
  });
  test('area anchors handle longitude wrapping at the date line', () {
    final layer = PropertyLayer(
      id: 'a',
      kind: LayerKind.area,
      name: 'Area',
      points: points([
        [30, 179.999],
        [30, -179.999],
        [30.001, -179.999],
        [30.001, 179.999],
      ]),
    );
    final label = MapMeasurementLabel.forLayer(
      layer,
      metric: false,
      geometry: geometry,
      areaResult: geometry.calculate(layer.points),
    )!;
    expect(label.longitude.abs(), closeTo(180, .000001));
  });
}
