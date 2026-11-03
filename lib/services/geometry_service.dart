import 'dart:math' as math;

import 'package:geobase/geobase.dart';

import '../models/property.dart';

class GeometryResult {
  final List<String> errors;
  final double? squareMeters;
  final double? perimeterMeters;
  final List<double> segments;
  final Geographic? center;
  const GeometryResult({
    this.errors = const [],
    this.squareMeters,
    this.perimeterMeters,
    this.segments = const [],
    this.center,
  });
  bool get valid => errors.isEmpty && squareMeters != null;
  double? get acres =>
      squareMeters == null ? null : squareMeters! / 4046.8564224;
  double? get squareFeet =>
      squareMeters == null ? null : squareMeters! / 0.09290304;
  double? get hectares => squareMeters == null ? null : squareMeters! / 10000;
}

/// WGS84 ellipsoidal distances and area of polygons bounded by geodesics.
/// Area integrates the ellipsoid surface primitive Q(phi) d(lambda) along
/// Vincenty geodesics using composite Simpson quadrature. No planar area is used.
/// Supported property extent: all points within 100 km of the first, |lat| <= 85.
class GeometryService {
  static const a = 6378137.0;
  static const e2 = 0.0066943799901413165;
  static const rad = math.pi / 180;
  bool validCoordinate(BoundaryPoint p) =>
      p.latitude.isFinite &&
      p.longitude.isFinite &&
      p.latitude.abs() <= 90 &&
      p.longitude.abs() <= 180;
  double distance(BoundaryPoint a, BoundaryPoint b) {
    if (!validCoordinate(a) || !validCoordinate(b)) {
      throw const FormatException('Invalid coordinate');
    }
    final d = a.geographic.vincenty().distanceTo(b.geographic);
    if (!d.isFinite) {
      throw const FormatException('Geodesic did not converge');
    }
    return d;
  }

  double pathLength(List<BoundaryPoint> points) {
    var sum = 0.0;
    for (var i = 1; i < points.length; i++) {
      sum += distance(points[i - 1], points[i]);
    }
    return sum;
  }

  BoundaryPoint midpoint(
    BoundaryPoint p,
    BoundaryPoint q, {
    required String label,
  }) {
    final m = p.geographic.vincenty().midPointTo(q.geographic);
    return BoundaryPoint(
      id: newId(),
      label: label,
      latitude: m.lat,
      longitude: m.lon,
    );
  }

  double _q(double phi) {
    final s = math.sin(phi), e = math.sqrt(e2);
    return a *
        a *
        (1 - e2) /
        2 *
        (s / (1 - e2 * s * s) + math.log((1 + e * s) / (1 - e * s)) / (2 * e));
  }

  GeometryResult calculate(List<BoundaryPoint> points) {
    if (points.length < 3) {
      return const GeometryResult(
        errors: ['At least three boundary points are required.'],
      );
    }
    if (points.any((p) => !validCoordinate(p))) {
      return const GeometryResult(
        errors: ['Latitude must be −90…90 and longitude −180…180.'],
      );
    }
    if (points.any((p) => p.latitude.abs() > 85)) {
      return const GeometryResult(
        errors: ['Measurements above 85° latitude are not supported.'],
      );
    }
    try {
      for (var i = 0; i < points.length; i++) {
        if (distance(points.first, points[i]) > 100000) {
          return const GeometryResult(
            errors: ['Property extent exceeds the supported 100 km radius.'],
          );
        }
        for (var j = i + 1; j < points.length; j++) {
          if (distance(points[i], points[j]) < 0.001) {
            return const GeometryResult(
              errors: ['Duplicate boundary points. Move or delete a point.'],
            );
          }
        }
      }
      // Gnomonic projection for intersection checks: ellipsoid
      // geodesics are sampled every <= 250 m before intersection validation.
      final ref = points.first.geographic;
      final projected = <List<math.Point<double>>>[];
      math.Point<double> project(Geographic p) {
        final lat = p.lat * rad, lat0 = ref.lat * rad;
        final lon = ((p.lon - ref.lon + 540) % 360 - 180) * rad;
        final cosc =
            math.sin(lat0) * math.sin(lat) +
            math.cos(lat0) * math.cos(lat) * math.cos(lon);
        return math.Point(
          a * math.cos(lat) * math.sin(lon) / cosc,
          a *
              (math.cos(lat0) * math.sin(lat) -
                  math.sin(lat0) * math.cos(lat) * math.cos(lon)) /
              cosc,
        );
      }

      final segments = <double>[];
      var area = 0.0;
      final baseline = _q(ref.lat * rad);
      for (var i = 0; i < points.length; i++) {
        final start = points[i].geographic,
            end = points[(i + 1) % points.length].geographic;
        final geodesic = start.vincenty();
        final d = distance(points[i], points[(i + 1) % points.length]);
        segments.add(d);
        final subdivisions = math.max(8, (d / 250).ceil());
        final n = subdivisions.isEven ? subdivisions : subdivisions + 1;
        var integral = 0.0;
        final line = <math.Point<double>>[];
        for (var k = 0; k <= n; k++) {
          final sample = geodesic.intermediatePointTo(end, fraction: k / n);
          final phi = sample.origin.lat * rad;
          final normal = a / math.sqrt(1 - e2 * math.pow(math.sin(phi), 2));
          final value =
              (_q(phi) - baseline) *
              math.sin(sample.bearing * rad) /
              (normal * math.cos(phi));
          integral +=
              value *
              (k == 0 || k == n
                  ? 1
                  : k.isEven
                  ? 2
                  : 4);
          line.add(project(sample.origin));
        }
        area += integral * d / (3 * n);
        projected.add(line);
      }
      for (var i = 0; i < points.length; i++) {
        // Adjacent edges may touch only at their common vertex; reject backtracking.
        final prev = project(
          points[(i + points.length - 1) % points.length].geographic,
        );
        final here = project(points[i].geographic);
        final next = project(points[(i + 1) % points.length].geographic);
        if (_orientation(prev, here, next).abs() < 1e-5 &&
            ((prev.x - here.x) * (next.x - here.x) +
                    (prev.y - here.y) * (next.y - here.y)) >
                0) {
          return const GeometryResult(errors: ['Boundary edges overlap.']);
        }
        for (var j = i + 1; j < points.length; j++) {
          if (j == i + 1 || (i == 0 && j == points.length - 1)) {
            continue;
          }
          for (var x = 1; x < projected[i].length; x++) {
            for (var y = 1; y < projected[j].length; y++) {
              if (_intersects(
                projected[i][x - 1],
                projected[i][x],
                projected[j][y - 1],
                projected[j][y],
              )) {
                return const GeometryResult(
                  errors: [
                    'Boundary crosses or touches itself. Adjust the point order or coordinates.',
                  ],
                );
              }
            }
          }
        }
      }
      if (!area.isFinite || area.abs() < 0.01) {
        return const GeometryResult(
          errors: ['Boundary has zero or negligible area.'],
        );
      }
      // Circular longitude mean handles properties spanning the antimeridian.
      final lat = points.fold(0.0, (s, p) => s + p.latitude) / points.length;
      final lon =
          math.atan2(
            points.fold(0.0, (s, p) => s + math.sin(p.longitude * rad)),
            points.fold(0.0, (s, p) => s + math.cos(p.longitude * rad)),
          ) /
          rad;
      return GeometryResult(
        squareMeters: area.abs(),
        perimeterMeters: segments.reduce((a, b) => a + b),
        segments: segments,
        center: Geographic(lat: lat, lon: lon),
      );
    } on Object {
      return const GeometryResult(
        errors: [
          'Unable to calculate this geometry. Check coordinates and extent.',
        ],
      );
    }
  }

  double _orientation(
    math.Point<double> a,
    math.Point<double> b,
    math.Point<double> c,
  ) => (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
  bool _intersects(
    math.Point<double> a,
    math.Point<double> b,
    math.Point<double> c,
    math.Point<double> d,
  ) {
    final o1 = _orientation(a, b, c),
        o2 = _orientation(a, b, d),
        o3 = _orientation(c, d, a),
        o4 = _orientation(c, d, b);
    bool on(math.Point<double> p, math.Point<double> q, math.Point<double> r) =>
        q.x >= math.min(p.x, r.x) - 1e-7 &&
        q.x <= math.max(p.x, r.x) + 1e-7 &&
        q.y >= math.min(p.y, r.y) - 1e-7 &&
        q.y <= math.max(p.y, r.y) + 1e-7;
    return (o1 * o2 < 0 && o3 * o4 < 0) ||
        (o1.abs() < 1e-7 && on(a, c, b)) ||
        (o2.abs() < 1e-7 && on(a, d, b)) ||
        (o3.abs() < 1e-7 && on(c, a, d)) ||
        (o4.abs() < 1e-7 && on(c, b, d));
  }
}
