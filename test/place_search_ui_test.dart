import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:lando/screens/map_screen.dart';
import 'map_screen_test.dart' show MapHarness, MemoryRepository;
import 'support/assistant_fixtures.dart' show exampleProperty;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'submitting and selecting an address resolves its place ID and centers the map',
    (tester) async {
      GoogleMapsFlutterPlatform.instance = MapHarness();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const places = MethodChannel('lando/places'),
          gps = MethodChannel('flutter.baseflow.com/geolocator');
      final calls = <String>[];
      messenger.setMockMethodCallHandler(gps, (_) async => 1);
      messenger.setMockMethodCallHandler(places, (call) async {
        calls.add(call.method);
        if (call.method == 'search') {
          expect(call.arguments, {'query': '123 Example Dr, Testville, TN'});
          return [
            {
              'name': '123 Example Dr, Testville, TN, USA',
              'placeId': 'chosen-place',
            },
          ];
        }
        expect(call.arguments['placeId'], 'chosen-place');
        return {
          'name': '123 Example Dr, Testville, TN, USA',
          'latitude': 35.05,
          'longitude': -89.66,
          'placeId': 'chosen-place',
        };
      });
      final repo = MemoryRepository();
      await repo.save(exampleProperty());
      await tester.pumpWidget(
        MaterialApp(
          home: MapScreen(
            repository: repo,
            themeMode: ThemeMode.light,
            onTheme: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Search address'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.enterText(
        find.byType(TextField),
        '123 Example Dr, Testville, TN',
      );
      await tester.tap(find.text('Done'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(calls, ['search']);
      await tester.tap(find.text('123 Example Dr, Testville, TN, USA'));
      await tester.pumpAndSettle();
      expect(calls, ['search', 'resolve']);
      expect(
        tester
            .widget<GoogleMap>(find.byType(GoogleMap))
            .initialCameraPosition
            .target,
        const LatLng(35.05, -89.66),
      );
      expect(find.textContaining('No matching'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(const SizedBox());
      messenger.setMockMethodCallHandler(places, null);
      messenger.setMockMethodCallHandler(gps, null);
    },
  );
}
