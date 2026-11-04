import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lando/services/place_search.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('lando/places');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test(
    'native search needs no proxy and forwards the map center as a location bias',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'search');
        expect(call.arguments, {
          'query': 'Austin',
          'latitude': 30.2,
          'longitude': -97.7,
        });
        return [
          {'name': 'Austin, TX', 'latitude': 30.2, 'longitude': -97.7},
        ];
      });
      final service = PlaceSearch(endpoint: '');
      final results = await service.search(
        ' Austin ',
        latitude: 30.2,
        longitude: -97.7,
      );
      expect(results.single.name, 'Austin, TX');
      service.dispose();
    },
  );
  test(
    'native configuration errors are actionable and never echo SDK credentials',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(
          code: 'places_error',
          message: 'secret-key-in-upstream-error',
        ),
      );
      final service = PlaceSearch(endpoint: '');
      await expectLater(
        service.search('Austin'),
        throwsA(
          isA<PlaceSearchException>().having(
            (e) => e.message,
            'safe setup guidance',
            allOf(contains('Places API (New)'), isNot(contains('secret-key'))),
          ),
        ),
      );
      service.dispose();
    },
  );
  test('search posts to HTTPS proxy and parses locations', () async {
    final search = PlaceSearch(
      endpoint: 'https://example.test/search',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.body, contains('Austin'));
        return http.Response(
          '{"places":[{"formattedAddress":"Austin, TX","location":{"latitude":30.2,"longitude":-97.7}}]}',
          200,
        );
      }),
    );
    final results = await search.search('Austin');
    expect(results.single.name, 'Austin, TX');
    expect(results.single.latitude, 30.2);
    search.dispose();
  });
  test(
    'search rejects insecure endpoint and reports service failures',
    () async {
      final insecure = PlaceSearch(endpoint: 'http://example.test');
      await expectLater(insecure.search('x'), throwsFormatException);
      insecure.dispose();
      final failing = PlaceSearch(
        endpoint: 'https://example.test',
        client: MockClient((_) async => http.Response('', 503)),
      );
      await expectLater(failing.search('x'), throwsFormatException);
      failing.dispose();
    },
  );
}
