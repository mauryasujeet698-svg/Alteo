import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import 'mapbox_service.dart';

/// Converts coordinates into a full delivery address without requiring the
/// customer to enter their coordinates or have a Mapbox token configured.
class CustomerLocationService {
  CustomerLocationService._();

  static String _s(String? value) => (value ?? '').trim();

  static List<String> _distinct(List<String?> raw) {
    final out = <String>[];
    for (final part in raw.map(_s).where((value) => value.isNotEmpty)) {
      if (out.isEmpty || out.last.toLowerCase() != part.toLowerCase()) out.add(part);
    }
    return out;
  }

  static Future<Map<String, dynamic>> resolveCoordinates(double latitude, double longitude) async {
    Placemark? placemark;
    String? onlineAddress;
    if (MapboxService.isConfigured) {
      onlineAddress = await MapboxService.reverseGeocode(longitude, latitude);
    }
    try {
      final results = await placemarkFromCoordinates(latitude, longitude)
          .timeout(const Duration(seconds: 12));
      if (results.isNotEmpty) placemark = results.first;
    } catch (_) {
      // Native address data is best effort. A user can still confirm the map pin.
    }

    final street = _distinct([placemark?.name, placemark?.street]).join(', ');
    final locality = _distinct([placemark?.subLocality, placemark?.thoroughfare]).join(', ');
    final city = _distinct([placemark?.locality]).join(', ');
    final district = _s(placemark?.subAdministrativeArea);
    final state = _s(placemark?.administrativeArea);
    final pin = _s(placemark?.postalCode);
    final country = _s(placemark?.country).isEmpty ? 'India' : _s(placemark?.country);
    final full = _s(onlineAddress).isNotEmpty
        ? _s(onlineAddress)
        : _distinct([
            street,
            locality,
            city,
            district,
            state,
            pin,
            country,
          ]).join(', ');
    final short = _distinct([
      locality.isNotEmpty ? locality : street,
      city.isNotEmpty ? city : district,
      pin,
    ]).join(' · ');

    return <String, dynamic>{
      'latitude': latitude,
      'longitude': longitude,
      'formatted_address': full.isEmpty ? 'Selected map location' : full,
      'display_address': short.isEmpty ? (full.isEmpty ? 'Selected map location' : full) : short,
      'address_line1': street.isNotEmpty ? street : locality,
      'locality': locality,
      'city': city.isNotEmpty ? city : district,
      'district': district,
      'state': state,
      'postal_code': pin,
      'country': country,
    };
  }

  static Future<Map<String, dynamic>?> currentLocationIfPermitted() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) return null;
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return resolveCoordinates(position.latitude, position.longitude);
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> searchAddress(String query) async {
    final coordinates = await MapboxService.geocode(query);
    if (coordinates == null || coordinates.length < 2) return null;
    return resolveCoordinates(coordinates[1], coordinates[0]);
  }
}
