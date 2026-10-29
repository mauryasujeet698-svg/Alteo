import 'dart:convert';
import 'dart:math' as math;

import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;

/// A route returned by the public map-routing API.
class MapboxRouteResult {
  const MapboxRouteResult({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.coordinates,
  });

  final double distanceMeters;
  final double durationSeconds;

  /// [longitude, latitude] coordinate pairs in route order.
  final List<List<double>> coordinates;
}

/// Map and address operations. A restricted public "pk." token is optional:
/// local/device geocoding and a non-provider map remain usable without it.
/// Never put a private "sk." map token in a mobile app.
class MapboxService {
  MapboxService._();

  static String _publicToken = '';
  static String? _lastError;

  static void configure(String publicToken) {
    _publicToken = publicToken.trim();
    _lastError = null;
    if (_publicToken.isNotEmpty && !_publicToken.startsWith('pk.')) {
      // Never surface token details in the customer UI.
      _lastError = 'Online road directions are temporarily unavailable.';
      _publicToken = '';
    }
  }

  static bool get isConfigured => _publicToken.startsWith('pk.');
  static String get publicToken => isConfigured ? _publicToken : '';
  static String? get lastError => _lastError;

  static String get configurationMessage =>
      'Road directions are temporarily unavailable. You can still select a location or search by address.';

  static void _setHttpError(int status) {
    _lastError = switch (status) {
      429 => 'Location search is busy right now. Please try again shortly.',
      401 || 403 => 'Online location search is unavailable. Try selecting the map or entering a nearby landmark.',
      _ => 'We could not load location details. Please try again.',
    };
  }

  static Future<List<double>?> _nativeGeocode(String address) async {
    final value = address.trim();
    if (value.length < 3) {
      _lastError = 'Enter an address, locality, landmark or PIN code.';
      return null;
    }
    try {
      final query = value.toLowerCase().contains('india') ? value : '$value, India';
      final results = await locationFromAddress(query).timeout(const Duration(seconds: 12));
      if (results.isEmpty) {
        _lastError = 'We could not find that location. Try a nearby landmark or select it on the map.';
        return null;
      }
      final point = results.first;
      if (point.latitude < -90 || point.latitude > 90 || point.longitude < -180 || point.longitude > 180) {
        _lastError = 'We could not identify that location. Please try another search.';
        return null;
      }
      _lastError = null;
      return [point.longitude, point.latitude];
    } catch (_) {
      _lastError = 'We could not find that address. Try a nearby landmark or select it on the map.';
      return null;
    }
  }

  static Future<String?> _nativeReverseGeocode(double longitude, double latitude) async {
    try {
      final places = await placemarkFromCoordinates(latitude, longitude)
          .timeout(const Duration(seconds: 12));
      if (places.isEmpty) {
        _lastError = 'Your point is selected, but its readable address is not available.';
        return null;
      }
      final p = places.first;
      final parts = <String>[
        p.name ?? '',
        p.street ?? '',
        p.subLocality ?? '',
        p.locality ?? '',
        p.subAdministrativeArea ?? '',
        p.administrativeArea ?? '',
        p.postalCode ?? '',
        p.country ?? '',
      ].map((s) => s.trim()).where((s) => s.isNotEmpty);
      final result = <String>[];
      for (final part in parts) {
        if (result.isEmpty || result.last.toLowerCase() != part.toLowerCase()) result.add(part);
      }
      _lastError = null;
      return result.isEmpty ? null : result.join(', ');
    } catch (_) {
      _lastError = 'Your point is selected. Add house and street details if the address cannot be resolved.';
      return null;
    }
  }

  /// Returns [longitude, latitude]. If online geocoding is unavailable, tries
  /// the device's address geocoder instead of failing solely because the token
  /// is absent.
  static Future<List<double>?> geocode(String address) async {
    final value = address.trim();
    if (value.length < 3) {
      _lastError = 'Enter an address, locality, landmark or PIN code.';
      return null;
    }
    if (!isConfigured) return await _nativeGeocode(value);

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
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        _setHttpError(response.statusCode);
        return _nativeGeocode(value);
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final features = decoded['features'] as List<dynamic>? ?? const [];
      if (features.isEmpty) return _nativeGeocode(value);
      final center = (features.first as Map<String, dynamic>)['center'] as List<dynamic>?;
      if (center == null || center.length < 2) return _nativeGeocode(value);
      final longitude = (center[0] as num).toDouble();
      final latitude = (center[1] as num).toDouble();
      if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) return _nativeGeocode(value);
      _lastError = null;
      return [longitude, latitude];
    } catch (_) {
      return _nativeGeocode(value);
    }
  }

  static Future<String?> reverseGeocode(double longitude, double latitude) async {
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
      _lastError = 'We could not identify that location. Please try again.';
      return null;
    }
    if (!isConfigured) return await _nativeReverseGeocode(longitude, latitude);

    final uri = Uri.https(
      'api.mapbox.com',
      '/geocoding/v5/mapbox.places/$longitude,$latitude.json',
      {'access_token': _publicToken, 'limit': '1', 'country': 'IN', 'language': 'en'},
    );
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        _setHttpError(response.statusCode);
        return _nativeReverseGeocode(longitude, latitude);
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final features = decoded['features'] as List<dynamic>? ?? const [];
      if (features.isEmpty) return _nativeReverseGeocode(longitude, latitude);
      final name = (features.first as Map<String, dynamic>)['place_name']?.toString().trim();
      _lastError = null;
      return name?.isNotEmpty == true ? name : await _nativeReverseGeocode(longitude, latitude);
    } catch (_) {
      return _nativeReverseGeocode(longitude, latitude);
    }
  }

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
    const profiles = {'driving', 'driving-traffic', 'walking', 'cycling'};
    if (!profiles.contains(profile) ||
        startLatitude < -90 || startLatitude > 90 ||
        endLatitude < -90 || endLatitude > 90 ||
        startLongitude < -180 || startLongitude > 180 ||
        endLongitude < -180 || endLongitude > 180) {
      _lastError = 'Choose valid pickup and destination locations.';
      return null;
    }
    final coordinatePath = '$startLongitude,$startLatitude;$endLongitude,$endLatitude';
    final uri = Uri.https(
      'api.mapbox.com',
      '/directions/v5/mapbox/$profile/$coordinatePath',
      {'access_token': _publicToken, 'overview': 'full', 'geometries': 'geojson', 'steps': 'false'},
    );
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        _setHttpError(response.statusCode);
        return null;
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = decoded['routes'] as List<dynamic>? ?? const [];
      if (routes.isEmpty) {
        _lastError = 'No road route was found between those locations.';
        return null;
      }
      final route = routes.first as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>?;
      final raw = geometry?['coordinates'] as List<dynamic>? ?? const [];
      final points = <List<double>>[];
      for (final item in raw) {
        if (item is List && item.length >= 2 && item[0] is num && item[1] is num) {
          points.add([(item[0] as num).toDouble(), (item[1] as num).toDouble()]);
        }
      }
      final distance = (route['distance'] as num?)?.toDouble();
      final duration = (route['duration'] as num?)?.toDouble();
      if (distance == null || duration == null || points.length < 2) {
        _lastError = 'A road route could not be calculated right now.';
        return null;
      }
      _lastError = null;
      return MapboxRouteResult(distanceMeters: distance, durationSeconds: duration, coordinates: points);
    } catch (_) {
      _lastError = 'A road route could not be calculated right now.';
      return null;
    }
  }

  static double straightLineDistanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const radius = 6371000.0;
    double radians(double deg) => deg * math.pi / 180.0;
    final dLat = radians(lat2 - lat1);
    final dLon = radians(lon2 - lon1);
    final a = (math.sin(dLat / 2) * math.sin(dLat / 2)) +
        math.cos(radians(lat1)) * math.cos(radians(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    return 2 * radius * math.asin(math.sqrt(a.clamp(0.0, 1.0).toDouble()));
  }
}
