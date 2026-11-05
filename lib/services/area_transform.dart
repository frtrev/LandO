import 'package:geobase/geobase.dart';
import '../models/property.dart';
import 'geometry_service.dart';

/// Always transforms an immutable gesture-start snapshot, avoiding cumulative
/// slider drift. WGS84 distances/bearings also handle longitude wrapping.
class AreaTransform {
  final List<BoundaryPoint> points;
  final Geographic center;
  final List<({double distance, double bearing})> offsets;
  AreaTransform._(this.points, this.center, this.offsets);
  factory AreaTransform(List<BoundaryPoint> points, GeometryService geometry) {
    final result = geometry.calculate(points);
    if (!result.valid) throw StateError('Select a valid custom area first.');
    final center = result.center!;
    return AreaTransform._(List.unmodifiable(points), center, [
      for (final point in points)
        (
          distance: geometry.distance(
            BoundaryPoint(
              id: '',
              label: '',
              latitude: center.lat,
              longitude: center.lon,
            ),
            point,
          ),
          bearing: center == point.geographic
              ? 0
              : center.vincenty().initialBearingTo(point.geographic),
        ),
    ]);
  }
  List<BoundaryPoint> apply({
    double scale = 1,
    double degrees = 0,
    Geographic? target,
  }) {
    if (!scale.isFinite || scale <= 0 || !degrees.isFinite) {
      throw ArgumentError('Invalid area transform.');
    }
    final origin = target ?? center;
    if (scale == 1 && degrees == 0 && origin == center) return List.of(points);
    return [
      for (var i = 0; i < points.length; i++) _move(i, origin, scale, degrees),
    ];
  }

  BoundaryPoint _move(int i, Geographic origin, double scale, double degrees) {
    final offset = offsets[i];
    final position = offset.distance < .000001
        ? origin
        : origin.vincenty().destinationPoint(
            distance: offset.distance * scale,
            bearing: offset.bearing + degrees,
          );
    return points[i].move(position.lat, position.lon);
  }

  List<BoundaryPoint> drag(Geographic from, Geographic to) {
    if (from == to) return List.of(points);
    final distance = from.vincenty().distanceTo(to);
    if (distance < .000001) return List.of(points);
    final target = center.vincenty().destinationPoint(
      distance: distance,
      bearing: from.vincenty().initialBearingTo(to),
    );
    return apply(target: target);
  }
}
