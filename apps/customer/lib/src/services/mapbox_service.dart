import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Only a public, platform-restricted Mapbox token may be shipped in the app.
class MapboxService {
  MapboxService._();
  static bool _configured = false;

  static void configure(String publicToken) {
    if (publicToken.trim().isEmpty) {
      _configured = false;
      return;
    }
    MapboxOptions.setAccessToken(publicToken);
    _configured = true;
  }

  static bool get isConfigured => _configured;
}
