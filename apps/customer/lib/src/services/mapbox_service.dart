import 'dart:convert';
import 'dart:math' as _math;
import 'package:http/http.dart' as http;

/// Mapbox client APIs used by the customer app.
/// Only a public (pk.) token may be embedded in a mobile app. Never use an sk. token.
class MapboxRouteResult {
  const MapboxRouteResult({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.coordinates,
  });
  final double distanceMeters;
  final double durationSeconds;
  /// Mapbox geometry coordinates in [longitude, latitude] order.
  final List<List<double>> coordinates;
}

class MapboxService {
  MapboxService._();

  static String _publicToken = '';
  static String? _lastError;

  static void configure(String publicToken) {
    _publicToken = publicToken.trim();
    _lastError = null;
    if (_publicToken.isNotEmpty && !_publicToken.startsWith('pk.')) {
      _lastError = 'Map features are temporarily unavailable. You can enter an address manually.';
    }
  }

  static bool get isConfigured => _publicToken.startsWith('pk.');
  static String? get lastError => _lastError;
  static String get publicToken => isConfigured ? _publicToken : '';

  static String get configurationMessage => 'Map search is temporarily unavailable. You can still enter an address manually.';

  static void _setHttpError(String api, int status) {
    _lastError = switch (status) {
      429 => 'Location search is busy right now. Please try again shortly.',
      401 || 403 => 'Map search is temporarily unavailable. You can enter an address manually.',
      _ => 'Could not load map details right now. Please try again shortly.',
    };
  }

  /// Forward-geocodes an address in India to [longitude, latitude].
  static Future<List<double>?> geocode(String address) async {
    if (!isConfigured) {
      _lastError = configurationMessage;
      return null;
    }
    final value = address.trim();
    if (value.length < 3) {
      _lastError = 'Enter at least 3 characters of an address or landmark.';
      return null;
    }

    // Let Uri encode the address as a single path segment. Pre-encoding it
    // first would double-encode percent signs and break many searches.
    final uri = Uri(
      scheme: 'https',
      host: 'api.mapbox.com',
      pathSegments: ['geocoding', 'v5', 'mapbox.places', '$value.json'],
      queryParameters: {
        'access_token': _publicToken,
        'limit': '1',
        'country': 'IN',
        'language': 'en',
        'types': 'address,street,neighborhood,locality,place,postcode',
      },
    );
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        _setHttpError('Mapbox address search', response.statusCode);
        return null;
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final features = decoded['features'] as List<dynamic>? ?? const [];
      if (features.isEmpty) {
        _lastError = 'No matching Indian address found. Try a nearby landmark or add the town/district.';
        return null;
      }
      final center = (features.first as Map<String, dynamic>)['center'] as List<dynamic>?;
      if (center == null || center.length < 2) {
        _lastError = 'We could not identify that location. Try a nearby landmark.';
        return null;
      }
      final longitude = (center[0] as num).toDouble();
      final latitude = (center[1] as num).toDouble();
      if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
        _lastError = 'We could not identify that location. Try a nearby landmark.';
        return null;
      }
      _lastError = null;
      return [longitude, latitude];
    } catch (e) {
      _lastError = 'Mapbox address search could not connect. Check your internet connection and retry.';
      return null;
    }
  }

  /// Reverse-geocodes GPS coordinates to a readable address.
  static Future<String?> reverseGeocode(double longitude, double latitude) async {
    if (!isConfigured) {
      _lastError = configurationMessage;
      return null;
    }
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
      _lastError = 'Invalid GPS coordinates.';
      return null;
    }
    final uri = Uri.https(
      'api.mapbox.com',
      '/geocoding/v5/mapbox.places/$longitude,$latitude.json',
      {'access_token': _publicToken, 'limit': '1', 'country': 'IN', 'language': 'en'},
    );
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        _setHttpError('Mapbox reverse geocoding', response.statusCode);
        return null;
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final features = decoded['features'] as List<dynamic>? ?? const [];
      if (features.isEmpty) {
        _lastError = 'We found your location, but could not read its address yet.';
        return null;
      }
      final feature = features.first as Map<String, dynamic>;
      final name = feature['place_name'] as String?;
      _lastError = null;
      return name?.trim().isNotEmpty == true ? name : null;
    } catch (_) {
      _lastError = 'We found your location, but could not read its address yet.';
      return null;
    }
  }

  /// Gets a road route and ETA using Mapbox Directions. Coordinates are [lng, lat].
  static Future<MapboxRouteResult?> directions({
    required double startLongitude,
    required double startLatitude,
    required double endLongitude,
    required double endLatitude,
    String profile = 'driving',
  }) async {
    if (!isConfigured) {
      _lastError = configurationMessage;
      return null;
    }
    const allowedProfiles = {'driving', 'driving-traffic', 'walking', 'cycling'};
    if (!allowedProfiles.contains(profile)) {
      _lastError = 'That route option is not available right now.';
      return null;
    }
    final coordinates = '$startLongitude,$startLatitude;$endLongitude,$endLatitude';
    final uri = Uri.https(
      'api.mapbox.com',
      '/directions/v5/mapbox/$profile/$coordinates',
      {
        'access_token': _publicToken,
        'overview': 'full',
        'geometries': 'geojson',
        'steps': 'false',
      },
    );
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        _setHttpError('Mapbox directions', response.statusCode);
        return null;
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = decoded['routes'] as List<dynamic>? ?? const [];
      if (routes.isEmpty) {
        _lastError = 'We could not find a road route between those locations. Check the addresses.';
        return null;
      }
      final route = routes.first as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>?;
      final rawCoordinates = geometry?['coordinates'] as List<dynamic>? ?? const [];
      final points = <List<double>>[];
      for (final raw in rawCoordinates) {
        if (raw is List && raw.length >= 2 && raw[0] is num && raw[1] is num) {
          points.add([(raw[0] as num).toDouble(), (raw[1] as num).toDouble()]);
        }
      }
      final distance = (route['distance'] as num?)?.toDouble();
      final duration = (route['duration'] as num?)?.toDouble();
      if (distance == null || duration == null || points.length < 2) {
        _lastError = 'A route estimate is temporarily unavailable.';
        return null;
      }
      _lastError = null;
      return MapboxRouteResult(distanceMeters: distance, durationSeconds: duration, coordinates: points);
    } catch (_) {
      _lastError = 'Route details could not load. Check your connection and try again.';
      return null;
    }
  }

  /// Great-circle distance estimate for graceful fallback when no route API is available.
  static double straightLineDistanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0;
    double radians(double degrees) => degrees * 3.141592653589793 / 180.0;
    final dLat = radians(lat2 - lat1);
    final dLon = radians(lon2 - lon1);
    final a = (mathSin(dLat / 2) * mathSin(dLat / 2)) +
        mathCos(radians(lat1)) * mathCos(radians(lat2)) *
        mathSin(dLon / 2) * mathSin(dLon / 2);
    final clamped = a.clamp(0.0, 1.0).toDouble();
    return 2 * earthRadius * mathAsin(mathSqrt(clamped));
  }
}

double mathSin(double value) => _math.sin(value);
double mathCos(double value) => _math.cos(value);
double mathAsin(double value) => _math.asin(value);
double mathSqrt(double value) => _math.sqrt(value);
