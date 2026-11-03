import 'package:geobase/geobase.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

class BoundaryPoint {
  final String id;
  final String label;
  final double latitude;
  final double longitude;
  const BoundaryPoint({
    required this.id,
    required this.label,
    required this.latitude,
    required this.longitude,
  });
  Geographic get geographic => Geographic(lat: latitude, lon: longitude);
  BoundaryPoint move(double lat, double lon) =>
      BoundaryPoint(id: id, label: label, latitude: lat, longitude: lon);
  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'lat': latitude,
    'lon': longitude,
  };
  factory BoundaryPoint.fromJson(Map<String, dynamic> j) => BoundaryPoint(
    id: j['id'] as String,
    label: j['label'] as String,
    latitude: (j['lat'] as num).toDouble(),
    longitude: (j['lon'] as num).toDouble(),
  );
}

String pointLabel(int index) {
  var n = index + 1;
  var label = '';
  while (n > 0) {
    n--;
    label = String.fromCharCode(65 + n % 26) + label;
    n ~/= 26;
  }
  return label;
}

class Property {
  final String id;
  String name;
  String description;
  List<BoundaryPoint> points;
  double latitude;
  double longitude;
  double zoom;
  double bearing;
  double tilt;
  bool metric;
  final DateTime created;
  DateTime modified;
  int nextLabel;
  Property({
    required this.id,
    required this.name,
    required this.points,
    required this.latitude,
    required this.longitude,
    this.description = '',
    this.zoom = 18,
    this.bearing = 0,
    this.tilt = 0,
    this.metric = false,
    required this.created,
    required this.modified,
    this.nextLabel = 4,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'points': points.map((p) => p.toJson()).toList(),
    'latitude': latitude,
    'longitude': longitude,
    'zoom': zoom,
    'bearing': bearing,
    'tilt': tilt,
    'metric': metric,
    'created': created.toIso8601String(),
    'modified': modified.toIso8601String(),
    'nextLabel': nextLabel,
  };
  factory Property.fromJson(Map<String, dynamic> j) => Property(
    id: j['id'] as String,
    name: j['name'] as String,
    description: j['description'] as String,
    points: (j['points'] as List)
        .map((p) => BoundaryPoint.fromJson(Map<String, dynamic>.from(p)))
        .toList(),
    latitude: (j['latitude'] as num).toDouble(),
    longitude: (j['longitude'] as num).toDouble(),
    zoom: (j['zoom'] as num).toDouble(),
    bearing: (j['bearing'] as num?)?.toDouble() ?? 0,
    tilt: (j['tilt'] as num?)?.toDouble() ?? 0,
    metric: j['metric'] as bool,
    created: DateTime.parse(j['created'] as String),
    modified: DateTime.parse(j['modified'] as String),
    nextLabel: j['nextLabel'] as int,
  );
}
