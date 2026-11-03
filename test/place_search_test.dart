import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lando/services/place_search.dart';

void main() {
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
