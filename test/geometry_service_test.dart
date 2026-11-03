import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lando/models/property.dart';
import 'package:lando/services/geometry_service.dart';

List<BoundaryPoint> points(List<List<num>> coords) => List.generate(
  coords.length,
  (i) => BoundaryPoint(
    id: '$i',
    label: pointLabel(i),
    latitude: coords[i][0].toDouble(),
    longitude: coords[i][1].toDouble(),
  ),
);
void main() {
  final geometry = GeometryService();
  final fixtures =
      jsonDecode(File('test/geographiclib_fixtures.json').readAsStringSync())
          as List;
  for (final fixture in fixtures) {
    final coords = (fixture['coords'] as List)
        .map((p) => (p as List).cast<num>())
        .toList();
    test('WGS84 GeographicLib reference: ${fixture['name']}', () {
      final p = points(coords), result = geometry.calculate(p);
      expect(result.errors, isEmpty);
      expect(
        result.squareMeters,
        closeTo(fixture['area'] as num, (fixture['area'] as num) * 1e-7 + .002),
      );
      expect(
        result.perimeterMeters,
        closeTo(fixture['perimeter'] as num, .001),
      );
      final reverse = geometry.calculate(p.reversed.toList());
      expect(reverse.squareMeters, closeTo(result.squareMeters!, .002));
      expect(
        result.segments.reduce((a, b) => a + b),
        closeTo(result.perimeterMeters!, 1e-8),
      );
      expect(result.acres! * 4046.8564224, closeTo(result.squareMeters!, 1e-6));
      expect(
        result.squareFeet! * .09290304,
        closeTo(result.squareMeters!, 1e-6),
      );
      expect(result.hectares! * 10000, closeTo(result.squareMeters!, 1e-6));
    });
  }
  test(
    'rejects invalid, duplicate, crossing, collinear and tiny boundaries',
    () {
      for (final coords in <List<List<num>>>[
        [
          [0, 0],
          [0, 1],
        ],
        [
          [91, 0],
          [0, 1],
          [1, 1],
        ],
        [
          [double.nan, 0],
          [0, 1],
          [1, 1],
        ],
        [
          [0, 0],
          [0, .001],
          [0, .001],
          [.001, 0],
        ],
        [
          [0, 0],
          [.001, .001],
          [0, .001],
          [.001, 0],
        ],
        [
          [0, 0],
          [0, .001],
          [0, .002],
        ],
        [
          [0, 0],
          [0, .00000001],
          [.00000001, 0],
        ],
        [
          [86, 0],
          [86, .01],
          [86.01, 0],
        ],
        [
          [0, 0],
          [0, 2],
          [1, 0],
        ],
        [
          [0, 0],
          [0, .002],
          [0, .001],
          [.001, 0],
        ],
      ]) {
        final result = geometry.calculate(points(coords));
        expect(result.valid, isFalse);
        expect(result.squareMeters, isNull);
        expect(result.perimeterMeters, isNull);
      }
    },
  );
  test(
    'independent open path excludes closing edge and handles empty path',
    () {
      final p = points([
        [0, 0],
        [0, .001],
        [.001, .001],
      ]);
      expect(geometry.pathLength(p), closeTo(222, 1));
      expect(geometry.pathLength([]), 0);
      expect(geometry.pathLength([p.first]), 0);
    },
  );
  test('midpoint and stable labels support insertion without reordering', () {
    final p = points([
      [30, -98],
      [30, -97.999],
      [30.001, -97.999],
      [30.001, -98],
    ]);
    final middle = geometry.midpoint(p[1], p[2], label: 'E');
    final original = geometry.calculate(p);
    p.insert(2, middle);
    final result = geometry.calculate(p);
    expect(p.map((p) => p.label), ['A', 'B', 'E', 'C', 'D']);
    expect(result.squareMeters, closeTo(original.squareMeters!, .002));
    expect(pointLabel(26), 'AA');
  });
}
