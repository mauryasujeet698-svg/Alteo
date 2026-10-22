import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class PlaceSuggestion {
  const PlaceSuggestion({required this.label, required this.longitude, required this.latitude});
  final String label;
  final double longitude;
  final double latitude;
}

/// Only a public, platform-restricted Mapbox token may be shipped in the app.
class MapboxService {
  MapboxService._();
  static bool _configured = false;
  static String _accessToken = '';

  static void configure(String publicToken) {
    _accessToken = publicToken.trim();
    if (_accessToken.isEmpty) {
      _configured = false;
      return;
    }
    MapboxOptions.setAccessToken(_accessToken);
    _configured = true;
  }

  static bool get isConfigured => _configured;

  /// India-restricted place suggestions using Mapbox's public Geocoding API.
  static Future<List<PlaceSuggestion>> searchPlaces(String query) async {
    final term = query.trim();
    if (!_configured || term.length < 3) return const [];
    final uri = Uri.https(
      'api.mapbox.com',
      '/geocoding/v5/mapbox.places/$term.json',
      {
        'access_token': _accessToken,
        'country': 'in',
        'limit': '6',
        'autocomplete': 'true',
        'language': 'en',
        'types': 'address,poi,place,locality,neighborhood',
      },
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw StateError('Map search failed (' + response.statusCode.toString() + '). Check public token restrictions.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['features'] is! List) {
      throw StateError('Map provider returned an invalid response.');
    }
    final results = <PlaceSuggestion>[];
    for (final feature in decoded['features'] as List) {
      if (feature is! Map<String, dynamic>) continue;
      final label = feature['place_name'];
      final center = feature['center'];
      if (label is! String || center is! List || center.length < 2) continue;
      final longitude = (center[0] as num?)?.toDouble();
      final latitude = (center[1] as num?)?.toDouble();
      if (longitude == null || latitude == null) continue;
      results.add(PlaceSuggestion(label: label, longitude: longitude, latitude: latitude));
    }
    return results;
  }
}
