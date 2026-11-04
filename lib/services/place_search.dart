import 'dart:convert';
import 'dart:async';
import 'package:flutter/services.dart';

import 'package:http/http.dart' as http;

class PlaceResult {
  final String name;
  final double? latitude;
  final double? longitude;
  final String? placeId;
  const PlaceResult(this.name, this.latitude, this.longitude, {this.placeId});
  bool get hasCoordinates =>
      latitude != null &&
      longitude != null &&
      latitude!.isFinite &&
      longitude!.isFinite &&
      latitude!.abs() <= 90 &&
      longitude!.abs() <= 180;
  factory PlaceResult.fromNative(Map<dynamic, dynamic> data) => PlaceResult(
    data['name'] as String,
    (data['latitude'] as num?)?.toDouble(),
    (data['longitude'] as num?)?.toDouble(),
    placeId: data['placeId'] as String?,
  );
}

/// Uses native Google Places SDKs by default. An explicitly configured HTTPS
/// proxy remains available for deployments that prefer server-side search.
class PlaceSearch {
  final String endpoint;
  final http.Client client;
  final MethodChannel channel;
  PlaceSearch({
    this.endpoint = const String.fromEnvironment('PLACES_PROXY_URL'),
    http.Client? client,
    this.channel = const MethodChannel('lando/places'),
  }) : client = client ?? http.Client();
  Future<List<PlaceResult>> search(
    String query, {
    double? latitude,
    double? longitude,
  }) async {
    query = query.trim();
    if (query.isEmpty || query.length > 300) {
      throw const PlaceSearchException(
        'Enter an address or place (up to 300 characters).',
      );
    }
    if (endpoint.trim().isEmpty) {
      final useBias =
          !query.contains(',') && !RegExp(r'^\d+\b').hasMatch(query);
      final results =
          await _native('search', {
                'query': query,
                if (useBias && latitude != null && longitude != null)
                  'latitude': latitude,
                if (useBias && latitude != null && longitude != null)
                  'longitude': longitude,
              })
              as List? ??
          [];
      return results
          .map((item) => PlaceResult.fromNative(item as Map))
          .where(
            (place) =>
                place.hasCoordinates || place.placeId?.isNotEmpty == true,
          )
          .toList();
    }
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

  /// Fetch coordinates only for the result the user selected. Autocomplete
  /// suggestions are not coordinates and must never be treated as (0, 0).
  Future<PlaceResult> resolve(PlaceResult place) async {
    if (place.hasCoordinates) return place;
    if (place.placeId == null || place.placeId!.isEmpty) {
      throw const PlaceSearchException(
        'No map location was returned for this result. Try a more complete address.',
      );
    }
    final data = await _native('resolve', {
      'placeId': place.placeId,
      'name': place.name,
    });
    final resolved = PlaceResult.fromNative(data as Map);
    if (!resolved.hasCoordinates) {
      throw const PlaceSearchException(
        'No map location was returned for this result. Try a more complete address.',
      );
    }
    return resolved;
  }

  Future<dynamic> _native(String method, Map<String, dynamic> arguments) async {
    try {
      return await channel
          .invokeMethod<dynamic>(method, arguments)
          .timeout(const Duration(seconds: 20));
    } on MissingPluginException {
      throw const PlaceSearchException(
        'Address search is available in the iOS and Android app. Rebuild and reinstall the app after updating.',
      );
    } on PlatformException catch (error) {
      if (error.code == 'places_selection_expired') {
        throw const PlaceSearchException(
          'That search result has expired. Search again and select the address.',
        );
      }
      if (error.code == 'places_not_configured') {
        throw const PlaceSearchException(
          'Configure a Google Maps/Places key for this app build to enable address search.',
        );
      }
      final details = error.details;
      throw PlaceSearchException(
        'Google Places search could not complete. Check your connection. If it persists, enable Places API (New), billing, and Places access for this app’s key in Google Cloud.',
        statusCode: details is Map && details['statusCode'] is int
            ? details['statusCode'] as int
            : null,
      );
    } on TimeoutException {
      throw const PlaceSearchException(
        'Address search timed out. Check your connection and try again.',
      );
    }
  }

  void dispose() => client.close();
}

class PlaceSearchException implements Exception {
  final String message;
  final int? statusCode;
  const PlaceSearchException(this.message, {this.statusCode});
  @override
  String toString() => message;
}
