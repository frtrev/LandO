import 'package:lando/models/property.dart';
import 'package:lando/services/property_repository.dart';
import 'package:sqflite/sqflite.dart';
import 'package:lando/services/assistant/api_key_store.dart';
import 'package:lando/services/assistant/assistant_provider.dart';

Property exampleProperty({String id = 'property'}) {
  final now = DateTime.utc(2026, 11, 3);
  final boundary = [
    const BoundaryPoint(id: 'a', label: 'A', latitude: 30, longitude: -98),
    const BoundaryPoint(id: 'b', label: 'B', latitude: 30, longitude: -97.999),
    const BoundaryPoint(
      id: 'c',
      label: 'C',
      latitude: 30.001,
      longitude: -97.999,
    ),
    const BoundaryPoint(id: 'd', label: 'D', latitude: 30.001, longitude: -98),
  ];
  return Property(
    id: id,
    name: 'My pasture',
    points: boundary,
    latitude: 30,
    longitude: -98,
    created: now,
    modified: now,
    layers: [
      PropertyLayer(
        id: 'garden',
        kind: LayerKind.area,
        name: 'Garden',
        points: List.from(boundary),
        nextLabel: 4,
      ),
      PropertyLayer(
        id: 'driveway',
        kind: LayerKind.distance,
        name: 'Driveway',
        points: boundary.take(2).toList(),
        nextLabel: 2,
      ),
    ],
  );
}

class MemoryKeyStore implements ApiKeyStore {
  String? key;
  String? geminiKey;
  MemoryKeyStore([this.key, this.geminiKey]);
  @override
  Future<String?> read({
    AssistantProvider provider = AssistantProvider.openai,
  }) async => provider == AssistantProvider.openai ? key : geminiKey;
  @override
  Future<void> save(
    String value, {
    AssistantProvider provider = AssistantProvider.openai,
  }) async {
    if (provider == AssistantProvider.openai) {
      key = value;
    } else {
      geminiKey = value;
    }
  }

  @override
  Future<void> delete({
    AssistantProvider provider = AssistantProvider.openai,
  }) async {
    if (provider == AssistantProvider.openai) {
      key = null;
    } else {
      geminiKey = null;
    }
  }
}

class ChatMemoryRepository implements PropertyRepository {
  final Map<String, String> preferences = {};
  final Map<String, Property> properties = {};
  @override
  Database get db => throw UnimplementedError();
  @override
  Future<List<Property>> list() async =>
      properties.values.map((p) => Property.fromJson(p.toJson())).toList();
  @override
  Future<String?> preference(String key) async => preferences[key];
  @override
  Future<void> setPreference(String key, String value) async {
    preferences[key] = value;
  }

  @override
  Future<void> save(Property property) async {
    properties[property.id] = Property.fromJson(property.toJson());
    preferences['lastProperty'] = property.id;
  }

  @override
  Future<void> delete(String id) async {
    properties.remove(id);
    preferences.remove('chat:$id');
  }
}
