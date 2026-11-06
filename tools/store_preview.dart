// Synthetic in-memory demo for Android store screenshots. Use a temporary
// emulator: flutter run -t tools/store_preview.dart -d EMULATOR_ID
// This entry point never opens the user's LandO property database.
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart' show inMemoryDatabasePath;
import 'package:lando/models/property.dart';
import 'package:lando/screens/map_screen.dart';
import 'package:lando/services/property_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = await PropertyRepository.open(
    databasePath: inMemoryDatabasePath,
  );
  const boundary = [
    BoundaryPoint(id: 'a', label: 'A', latitude: 30, longitude: -98),
    BoundaryPoint(id: 'b', label: 'B', latitude: 30, longitude: -97.999),
    BoundaryPoint(id: 'c', label: 'C', latitude: 30.001, longitude: -97.999),
    BoundaryPoint(id: 'd', label: 'D', latitude: 30.001, longitude: -98),
  ];
  final property = Property(
    id: 'store-demo',
    name: 'Demo pasture',
    description: 'Example planning boundary. Not an official parcel.',
    points: List.of(boundary),
    latitude: 30.0005,
    longitude: -97.9995,
    zoom: 17.6,
    created: DateTime.utc(2026),
    modified: DateTime.utc(2026),
    layers: [
      PropertyLayer(
        id: 'garden',
        name: 'Garden',
        kind: LayerKind.area,
        points: const [
          BoundaryPoint(
            id: 'ga',
            label: 'A',
            latitude: 30.0003,
            longitude: -97.9998,
          ),
          BoundaryPoint(
            id: 'gb',
            label: 'B',
            latitude: 30.0003,
            longitude: -97.9992,
          ),
          BoundaryPoint(
            id: 'gc',
            label: 'C',
            latitude: 30.0007,
            longitude: -97.9992,
          ),
          BoundaryPoint(
            id: 'gd',
            label: 'D',
            latitude: 30.0007,
            longitude: -97.9998,
          ),
        ],
      ),
      PropertyLayer(
        id: 'driveway',
        name: 'Driveway',
        kind: LayerKind.distance,
        points: boundary.take(2).toList(),
      ),
    ],
  );
  await repo.save(property);
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff197a59)),
      ),
      home: MapScreen(
        repository: repo,
        themeMode: ThemeMode.light,
        onTheme: (_) {},
      ),
    ),
  );
}
