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
    'address suggestions resolve only the selected place and ignore a distant map bias',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'search') {
          expect(call.arguments, {
            'query': '123 Example Drive Testville TN 38017',
          });
          return [
            {
              'name': '123 Example Drive, Testville, TN',
              'placeId': 'selected-id',
            },
            {
              'name': '123 Example Drive, Other City, TN',
              'placeId': 'other-id',
            },
          ];
        }
        expect(call.method, 'resolve');
        expect(call.arguments['placeId'], 'selected-id');
        return {
          'name': '123 Example Drive, Testville, TN',
          'placeId': 'selected-id',
          'latitude': 35.05,
          'longitude': -89.66,
        };
      });
      final service = PlaceSearch(endpoint: '');
      final results = await service.search(
        '123 Example Drive Testville TN 38017',
        latitude: 32.7,
        longitude: -96.7,
      );
      expect(calls, ['search']);
      expect(results.first.hasCoordinates, false);
      final selected = await service.resolve(results.first);
      expect(selected.hasCoordinates, true);
      expect(selected.latitude, 35.05);
      expect(calls, ['search', 'resolve']);
      expect(await service.resolve(selected), same(selected));
      expect(calls, ['search', 'resolve']);
      service.dispose();
    },
  );
  test(
    'expired selection asks for a new search without exposing native errors',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(
          code: 'places_selection_expired',
          message: 'private SDK payload',
        ),
      );
      final service = PlaceSearch(endpoint: '');
      await expectLater(
        service.resolve(
          const PlaceResult('A suggestion', null, null, placeId: 'old-id'),
        ),
        throwsA(
          isA<PlaceSearchException>().having(
            (e) => e.message,
            'retry guidance',
            allOf(contains('Search again'), isNot(contains('private'))),
          ),
        ),
      );
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
