import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'mapbox_service.dart';

/// Resolves a GPS point into a complete address using Mapbox when configured
/// and Android's native geocoder as a fallback.
class CustomerLocationService {
  CustomerLocationService._();

  static String _clean(String? value) => (value ?? '').trim();

  static String _join(Iterable<String?> parts) => parts
      .map(_clean)
      .where((part) => part.isNotEmpty)
      .fold<List<String>>(<String>[], (result, part) {
        if (result.isEmpty || result.last.toLowerCase() != part.toLowerCase()) result.add(part);
        return result;
      }).join(', ');

  static Future<Map<String, dynamic>> resolveCoordinates(double latitude, double longitude) async {
    Placemark? place;
    try {
      final results = await placemarkFromCoordinates(latitude, longitude);
      if (results.isNotEmpty) place = results.first;
    } catch (_) {
      // Native geocoding is best-effort; the coordinates remain usable.
    }

    String? mapboxAddress;
    if (MapboxService.isConfigured) {
      mapboxAddress = await MapboxService.reverseGeocode(longitude, latitude);
    }

    final street = _join([place?.name, place?.street]);
    final locality = _join([place?.subLocality, place?.thoroughfare]);
    final city = _join([place?.locality, place?.subAdministrativeArea]);
    final district = _clean(place?.subAdministrativeArea);
    final state = _clean(place?.administrativeArea);
    final pin = _clean(place?.postalCode);
    final fallbackFull = _join([
      street.isEmpty ? null : street,
      locality.isEmpty ? null : locality,
      city.isEmpty ? null : city,
      district.isEmpty ? null : district,
      state.isEmpty ? null : state,
      pin.isEmpty ? null : pin,
      _clean(place?.country).isEmpty ? 'India' : place!.country,
    ]);
    final fullAddress = _clean(mapboxAddress).isNotEmpty ? mapboxAddress!.trim() : fallbackFull;
    final shortAddress = _join([
      locality.isNotEmpty ? locality : (street.isNotEmpty ? street : null),
      city.isNotEmpty ? city : (district.isNotEmpty ? district : null),
      pin.isNotEmpty ? pin : null,
    ]);

    return <String, dynamic>{
      'latitude': latitude,
      'longitude': longitude,
      'formatted_address': fullAddress.isEmpty
          ? 'Selected map location'
          : fullAddress,
      'display_address': shortAddress.isEmpty
          ? (fullAddress.isEmpty ? 'Selected map location' : fullAddress)
          : shortAddress,
      'address_line1': street.isNotEmpty ? street : locality,
      'locality': locality,
      'city': city.isNotEmpty ? city : district,
      'district': district,
      'state': state,
      'postal_code': pin,
      'country': _clean(place?.country).isNotEmpty ? place!.country : 'India',
    };
  }

  /// Returns a location selection only when permission is already granted.
  /// The app's first-launch gate handles the initial permission prompt.
  static Future<Map<String, dynamic>?> currentLocationIfPermitted() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return null;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return await resolveCoordinates(position.latitude, position.longitude);
    } catch (_) {
      return null;
    }
  }

  /// Forward-geocodes a search string through Mapbox, with native address lookup
  /// performed by MapboxService when a token is not configured.
  static Future<Map<String, dynamic>?> searchAddress(String query) async {
    final coordinates = await MapboxService.geocode(query);
    if (coordinates == null || coordinates.length < 2) return null;
    return resolveCoordinates(coordinates[1], coordinates[0]);
  }
}
