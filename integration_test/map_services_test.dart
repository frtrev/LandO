// Opt-in real-device services: this performs one billable Google Places search.
// Set the simulator location to 32.7767,-96.7970 and grant location permission
// to app.neotheone.lando before running this test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lando/screens/map_screen.dart';
import 'package:lando/services/place_search.dart';
import '../test/map_screen_test.dart' show MemoryRepository;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('empty app centers on the simulator current location', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          repository: MemoryRepository(),
          themeMode: ThemeMode.light,
          onTheme: (_) {},
        ),
      ),
    );
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 250));
      final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
      if ((map.initialCameraPosition.target.latitude - 32.7767).abs() <
              .00001 &&
          (map.initialCameraPosition.target.longitude + 96.7970).abs() < .00001) {
        break;
      }
    }
    final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
    expect(map.initialCameraPosition.target.latitude, closeTo(32.7767, .00001));
    expect(
      map.initialCameraPosition.target.longitude,
      closeTo(-96.7970, .00001),
    );
    expect(map.myLocationEnabled, true);
    debugPrint(
      'STARTUP_GPS_PASSED: centered on the simulated Dallas location.',
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('native Google Places searches an address without a proxy', (
    tester,
  ) async {
    final search = PlaceSearch(endpoint: '');
    try {
      final results = await search.search(
        'Texas State Capitol, Austin, Texas',
        latitude: 30.2672,
        longitude: -97.7431,
      );
      expect(results, isNotEmpty);
      expect(results.first.latitude, closeTo(30.2747, .05));
      expect(results.first.longitude, closeTo(-97.7404, .05));
      debugPrint(
        'NATIVE_PLACES_PASSED: ${results.length} result(s), ${results.first.name}',
      );
    } on PlaceSearchException catch (error) {
      debugPrint(
        'NATIVE_PLACES_FAILED: service status ${error.statusCode}; ${error.message}',
      );
      rethrow;
    } finally {
      search.dispose();
    }
  });
}
