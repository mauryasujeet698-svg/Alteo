import 'dart:convert';
import 'package:http/http.dart' as http;

/// Lightweight map configuration. Only a public, URL-restricted Mapbox token
/// may be shipped in the client. OpenStreetMap tiles are used as a visual fallback.
class MapboxService {
  MapboxService._();
  static String _publicToken = '';

  static void configure(String publicToken) => _publicToken = publicToken.trim();
  static bool get isConfigured => _publicToken.isNotEmpty;
  static String get publicToken => _publicToken;

  /// Geocodes a user-entered Indian address to [longitude, latitude].
  /// Returns null when no public token is configured or the address cannot be resolved.
  static Future<List<double>?> geocode(String address) async {
    if (_publicToken.isEmpty || address.trim().length < 3) return null;
    final uri = Uri.https(
      'api.mapbox.com',
      '/geocoding/v5/mapbox.places/' + Uri.encodeComponent(address.trim()) + '.json',
      {'access_token': _publicToken, 'limit': '1', 'country': 'IN', 'language': 'en'},
    );
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final features = decoded['features'] as List<dynamic>? ?? const [];
      if (features.isEmpty) return null;
      final center = (features.first as Map<String, dynamic>)['center'] as List<dynamic>?;
      if (center == null || center.length < 2) return null;
      final longitude = (center[0] as num).toDouble();
      final latitude = (center[1] as num).toDouble();
      if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) return null;
      return [longitude, latitude];
    } catch (_) {
      return null;
    }
  }
}
