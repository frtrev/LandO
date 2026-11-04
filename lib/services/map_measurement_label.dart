import 'package:geobase/geobase.dart';

import '../models/property.dart';
import 'geometry_service.dart';

/// Geographic label anchors; presentation never changes stored geometry.
class MapMeasurementLabel {
  final String id, name, value;
  final double latitude, longitude;
  final bool area;
  const MapMeasurementLabel({
    required this.id,
    required this.name,
    required this.value,
    required this.latitude,
    required this.longitude,
    required this.area,
  });
  String get iconKey => '$area|$name|$value';

  static MapMeasurementLabel? forLayer(
    PropertyLayer layer, {
    required bool metric,
    required GeometryService geometry,
    GeometryResult? areaResult,
    double? distance,
  }) {
    if (layer.kind == LayerKind.area) {
      if (areaResult?.valid != true) return null;
      // Use the widest interior span at mid-height, so concave polygons do not
      // place their label in a notch. Unwrap longitude across the date line.
      final reference = layer.points.first.longitude;
      double unwrap(double lon) =>
          reference + (lon - reference + 540) % 360 - 180;
      final latitudes = layer.points.map((p) => p.latitude).toList()..sort();
      final lat = (latitudes.first + latitudes.last) / 2;
      final crossings = <double>[];
      for (var i = 0; i < layer.points.length; i++) {
        final a = layer.points[i],
            b = layer.points[(i + 1) % layer.points.length];
        if ((a.latitude > lat) != (b.latitude > lat)) {
          final x = unwrap(a.longitude), y = unwrap(b.longitude);
          crossings.add(
            x + (lat - a.latitude) / (b.latitude - a.latitude) * (y - x),
          );
        }
      }
      crossings.sort();
      if (crossings.length < 2) return null;
      var left = crossings[0], right = crossings[1];
      for (var i = 2; i + 1 < crossings.length; i += 2) {
        if (crossings[i + 1] - crossings[i] > right - left) {
          left = crossings[i];
          right = crossings[i + 1];
        }
      }
      return MapMeasurementLabel(
        id: layer.id,
        name: layer.name,
        value: layer.tagUnit(metric: metric).format(areaResult!.squareMeters!),
        latitude: lat,
        longitude: ((left + right) / 2 + 540) % 360 - 180,
        area: true,
      );
    }
    if (distance == null || distance <= 0 || layer.points.length < 2) {
      return null;
    }
    var remaining = distance / 2;
    for (var i = 1; i < layer.points.length; i++) {
      final a = layer.points[i - 1], b = layer.points[i];
      final segment = geometry.distance(a, b);
      if (remaining <= segment || i == layer.points.length - 1) {
        final position = a.geographic
            .vincenty()
            .intermediatePointTo(
              b.geographic,
              fraction: (remaining / segment).clamp(0, 1),
            )
            .origin;
        return MapMeasurementLabel(
          id: layer.id,
          name: layer.name,
          value: layer.tagUnit(metric: metric).format(distance),
          latitude: position.lat,
          longitude: position.lon,
          area: false,
        );
      }
      remaining -= segment;
    }
    return null;
  }
}
