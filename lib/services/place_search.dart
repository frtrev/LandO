import 'dart:convert';

import 'package:http/http.dart' as http;

class PlaceResult {
  final String name;
  final double latitude;
  final double longitude;
  const PlaceResult(this.name, this.latitude, this.longitude);
}

/// Calls an operator-controlled HTTPS proxy; the Google web-service key stays
/// server-side. The proxy forwards Places API (New) Text Search responses.
class PlaceSearch {
  final String endpoint;
  final http.Client client;
  PlaceSearch({
    this.endpoint = const String.fromEnvironment('PLACES_PROXY_URL'),
    http.Client? client,
  }) : client = client ?? http.Client();
  Future<List<PlaceResult>> search(String query) async {
    final uri = Uri.tryParse(endpoint);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException(
        'Configure PLACES_PROXY_URL with an HTTPS Places search proxy.',
      );
    }
    final response = await client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'textQuery': query.trim()}),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw const FormatException(
        'Address search failed. Check network and search service configuration.',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return ((body['places'] as List?) ?? []).map((p) {
      final location = p['location'] as Map<String, dynamic>;
      return PlaceResult(
        (p['formattedAddress'] ?? p['displayName']?['text'] ?? 'Place')
            as String,
        (location['latitude'] as num).toDouble(),
        (location['longitude'] as num).toDouble(),
      );
    }).toList();
  }

  void dispose() => client.close();
}
