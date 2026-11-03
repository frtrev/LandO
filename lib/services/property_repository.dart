import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/property.dart';

class PropertyRepository {
  final Database db;
  PropertyRepository(this.db);
  static Future<PropertyRepository> open({
    String? databasePath,
    DatabaseFactory? factory,
  }) async {
    final driver = factory ?? databaseFactory;
    final db = await driver.openDatabase(
      databasePath ?? path.join(await driver.getDatabasesPath(), 'lando.db'),
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE properties (id TEXT PRIMARY KEY, data TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE preferences (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
        },
      ),
    );
    return PropertyRepository(db);
  }

  Future<List<Property>> list() async {
    final rows = await db.query('properties');
    final properties = rows
        .map(
          (r) => Property.fromJson(
            jsonDecode(r['data'] as String) as Map<String, dynamic>,
          ),
        )
        .toList();
    properties.sort((a, b) => b.modified.compareTo(a.modified));
    return properties;
  }

  Future<void> save(Property property) async {
    await db.transaction((txn) async {
      await txn.insert('properties', {
        'id': property.id,
        'data': jsonEncode(property.toJson()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('preferences', {
        'key': 'lastProperty',
        'value': property.id,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> delete(String id) async {
    await db.transaction((txn) async {
      await txn.delete('properties', where: 'id = ?', whereArgs: [id]);
      await txn.delete(
        'preferences',
        where: 'key = ? AND value = ?',
        whereArgs: ['lastProperty', id],
      );
    });
  }

  Future<String?> preference(String key) async {
    final rows = await db.query(
      'preferences',
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setPreference(String key, String value) async {
    await db.insert('preferences', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
