// Opt-in live regression. Supply LANDO_ADDRESS_QUERY and optional
// LANDO_EXPECTED_CITY as dart defines; this performs billable Places calls.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lando/services/place_search.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'residential address resolves even when the map is in another state',
    (tester) async {
      const query = String.fromEnvironment('LANDO_ADDRESS_QUERY');
      const city = String.fromEnvironment('LANDO_EXPECTED_CITY');
      expect(
        query.isNotEmpty,
        true,
        reason: 'Supply LANDO_ADDRESS_QUERY for this opt-in live lookup.',
      );
      final service = PlaceSearch(endpoint: '');
      try {
        final results = await service.search(
          query,
          latitude: 32.7767,
          longitude: -96.7970,
        );
        debugPrint('RESIDENTIAL_LOOKUP_COUNT: ${results.length}');
        expect(
          results,
          isNotEmpty,
          reason:
              'A complete residential address must return a selectable result.',
        );
        final house = RegExp(r'^\d+').firstMatch(query)?.group(0);
        expect(
          results.any(
            (r) =>
                (house == null || r.name.contains(house)) &&
                (city.isEmpty ||
                    r.name.toLowerCase().contains(city.toLowerCase())),
          ),
          true,
          reason:
              'The result must match the requested house number and city, not only a street or nearby city.',
        );
        final selected = results.firstWhere(
          (r) =>
              (house == null || r.name.contains(house)) &&
              (city.isEmpty ||
                  r.name.toLowerCase().contains(city.toLowerCase())),
        );
        final resolved = await service.resolve(selected);
        expect(resolved.hasCoordinates, true);
        if (house != null) expect(resolved.name, contains(house));
        if (city.isNotEmpty) {
          expect(resolved.name.toLowerCase(), contains(city.toLowerCase()));
        }
        debugPrint('RESIDENTIAL_LOOKUP_PASSED');
      } finally {
        service.dispose();
      }
    },
  );
}
