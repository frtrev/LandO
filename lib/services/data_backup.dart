import 'dart:convert';
import 'dart:typed_data';

import '../models/chat_conversation.dart';
import '../models/property.dart';
import 'property_repository.dart';

/// A portable, versioned snapshot. Secure-storage credentials are not in SQLite.
class DataBackup {
  static const maxBytes = 50 * 1024 * 1024;
  final DateTime created;
  final List<Map<String, dynamic>> properties;
  final Map<String, String> preferences;
  DataBackup._(this.created, this.properties, this.preferences);

  static Future<DataBackup> capture(PropertyRepository repository) =>
      repository.db.transaction((txn) async {
        final rows = await txn.query('properties');
        final prefs = await txn.query('preferences');
        return DataBackup._(
          DateTime.now().toUtc(),
          rows
              .map(
                (r) => jsonDecode(r['data'] as String) as Map<String, dynamic>,
              )
              .toList(),
          {for (final r in prefs) r['key'] as String: r['value'] as String},
        );
      });

  String get fileName =>
      'LandO-backup-${created.toIso8601String().replaceAll(':', '-')}.lando.json';
  Uint8List encode() {
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': 'lando-backup',
          'version': 1,
          'databaseVersion': 1,
          'createdAt': created.toIso8601String(),
          'properties': properties,
          'preferences': preferences,
        }),
      ),
    );
    if (bytes.length > maxBytes) {
      throw const FormatException('Backup exceeds the 50 MB limit.');
    }
    return bytes;
  }

  factory DataBackup.decode(List<int> bytes) {
    if (bytes.length > maxBytes) {
      throw const FormatException('Backup exceeds the 50 MB limit.');
    }
    try {
      final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (j['format'] != 'lando-backup' ||
          j['version'] != 1 ||
          j['databaseVersion'] != 1) {
        throw const FormatException(
          'This file is not a supported LandO backup.',
        );
      }
      final backup = DataBackup._(
        DateTime.parse(j['createdAt'] as String),
        (j['properties'] as List)
            .map((p) => Map<String, dynamic>.from(p as Map))
            .toList(),
        Map<String, String>.from(j['preferences'] as Map),
      );
      final ids = <String>{};
      for (final p in backup.properties) {
        final property = _validateProperty(p);
        if (!ids.add(property.id)) {
          throw const FormatException('Duplicate property IDs.');
        }
      }
      final draft = backup.preferences['draft'];
      if (draft != null && draft.isNotEmpty) {
        _validateProperty(jsonDecode(draft) as Map<String, dynamic>);
      }
      for (final entry in backup.preferences.entries) {
        if (entry.key.startsWith('chat:') && entry.value.isNotEmpty) {
          ConversationArchive.fromStored(entry.value);
        }
      }
      return backup;
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException(
        'The backup is incomplete or contains invalid data.',
      );
    }
  }

  static Property _validateProperty(Map<String, dynamic> json) {
    final p = Property.fromJson(json);
    bool coordinate(double lat, double lon) =>
        lat.isFinite && lon.isFinite && lat.abs() <= 90 && lon.abs() <= 180;
    if (p.id.isEmpty ||
        !coordinate(p.latitude, p.longitude) ||
        !p.zoom.isFinite ||
        p.zoom < 0 ||
        p.zoom > 30 ||
        !p.bearing.isFinite ||
        !p.tilt.isFinite ||
        p.nextLabel < 0) {
      throw const FormatException(
        'Invalid property coordinates or identifiers.',
      );
    }
    final layerIds = <String>{};
    for (final layer in p.layers) {
      if (layer.id.isEmpty || !layerIds.add(layer.id) || layer.nextLabel < 0) {
        throw const FormatException('Invalid area or measurement identifiers.');
      }
    }
    for (final points in [p.points, ...p.layers.map((l) => l.points)]) {
      final pointIds = <String>{};
      for (final point in points) {
        if (point.id.isEmpty ||
            !pointIds.add(point.id) ||
            !coordinate(point.latitude, point.longitude)) {
          throw const FormatException(
            'Invalid boundary or measurement points.',
          );
        }
      }
    }
    return p;
  }

  int get conversationCount => preferences.entries
      .where((e) => e.key.startsWith('chat:') && e.value.isNotEmpty)
      .fold(
        0,
        (n, e) =>
            n + ConversationArchive.fromStored(e.value).conversations.length,
      );
  int get areaCount => properties.fold(
    0,
    (n, p) =>
        n +
        Property.fromJson(
          p,
        ).layers.where((l) => l.kind == LayerKind.area).length,
  );
  int get measurementCount => properties.fold(
    0,
    (n, p) =>
        n +
        Property.fromJson(
          p,
        ).layers.where((l) => l.kind == LayerKind.distance).length,
  );
  bool get hasDraft => preferences['draft']?.isNotEmpty == true;

  Future<void> restore(PropertyRepository repository) async {
    // Revalidate immediately before modifying storage. All deletes/inserts roll
    // back together if any write fails; no SQL is read from the backup file.
    final checked = DataBackup.decode(encode());
    await repository.db.transaction((txn) async {
      await txn.delete('properties');
      await txn.delete('preferences');
      for (final p in checked.properties) {
        await txn.insert('properties', {'id': p['id'], 'data': jsonEncode(p)});
      }
      for (final e in checked.preferences.entries) {
        // Consent belongs to the current installation, not to a shared backup.
        if (e.key.startsWith('assistantConsent:')) continue;
        await txn.insert('preferences', {'key': e.key, 'value': e.value});
      }
    });
  }
}
