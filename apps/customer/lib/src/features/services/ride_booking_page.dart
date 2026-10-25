import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/customer_auth_page.dart';
import '../../services/mapbox_service.dart';

class RideBookingPage extends StatefulWidget {
  const RideBookingPage({super.key, this.enableBackendQueries = true});
  final bool enableBackendQueries;
  @override
  State<RideBookingPage> createState() => _RideBookingPageState();
}

class _RideBookingPageState extends State<RideBookingPage> {
  final pickupController = TextEditingController();
  final destinationController = TextEditingController();
  List<double>? pickupCoordinates;
  List<double>? destinationCoordinates;
  String vehicleType = 'bike';
  bool locating = false;
  bool searchingPickup = false;
  bool searchingDestination = false;
  bool requestingRide = false;
  Map<String, dynamic>? fareQuote;

  @override
  void dispose() {
    pickupController.dispose();
    destinationController.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _useCurrentLocation() async {
    setState(() => locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _message('Turn on Location on your phone to use your current pickup point.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _message('Location permission is needed for current pickup. You can enter a pickup address manually instead.');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final address = await MapboxService.reverseGeocode(position.longitude, position.latitude);
      if (!mounted) return;
      setState(() {
        pickupCoordinates = [position.longitude, position.latitude];
        pickupController.text = address ?? 'Current location';
      });
      await _refreshQuote();
      if (address == null && !MapboxService.isConfigured) {
        _message('Current location is selected. Add a restricted Mapbox public token to show a readable address and search destinations.');
      }
    } catch (_) {
      _message('Could not get your current location. Try again or enter a pickup address.');
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  Future<void> _searchPickup() async {
    final value = pickupController.text.trim();
    if (value.length < 3) { _message('Enter a pickup address or use current location.'); return; }
    if (!MapboxService.isConfigured) { _message('Address search needs the restricted public Mapbox token in the app build.'); return; }
    setState(() => searchingPickup = true);
    try {
      final coords = await MapboxService.geocode(value);
      if (coords == null) { _message('Pickup not found. Try a fuller address or nearby landmark.'); return; }
      if (!mounted) return;
      setState(() => pickupCoordinates = coords);
      await _refreshQuote();
    } finally {
      if (mounted) setState(() => searchingPickup = false);
    }
  }

  Future<void> _searchDestination() async {
    final value = destinationController.text.trim();
    if (value.length < 3) { _message('Enter a destination address or landmark.'); return; }
    if (!MapboxService.isConfigured) { _message('Destination search needs the restricted public Mapbox token in the app build.'); return; }
    setState(() => searchingDestination = true);
    try {
      final coords = await MapboxService.geocode(value);
      if (coords == null) { _message('Destination not found. Try a fuller address or nearby landmark.'); return; }
      if (!mounted) return;
      setState(() => destinationCoordinates = coords);
      await _refreshQuote();
    } finally {
      if (mounted) setState(() => searchingDestination = false);
    }
  }

  Future<void> _refreshQuote() async {
    if (!widget.enableBackendQueries) { if (mounted) setState(() => fareQuote = {'enabled': false, 'message': 'Preview mode: live ride prices load when backend access is enabled.'}); return; }
    if (pickupCoordinates == null || destinationCoordinates == null) {
      if (mounted) setState(() => fareQuote = null);
      return;
    }
    try {
      final response = await Supabase.instance.client.rpc('quote_customer_ride', params: {
        'p_pickup_latitude': pickupCoordinates![1],
        'p_pickup_longitude': pickupCoordinates![0],
        'p_destination_latitude': destinationCoordinates![1],
        'p_destination_longitude': destinationCoordinates![0],
        'p_area_code': 'DEFAULT',
        'p_vehicle_type': vehicleType,
      });
      if (!mounted) return;
      setState(() => fareQuote = Map<String, dynamic>.from(response as Map));
    } catch (_) {
      if (mounted) setState(() => fareQuote = {
        'enabled': false,
        'message': 'Fare estimate is unavailable. Check that ride pricing and service availability are configured in Admin.',
      });
    }
  }

  Future<void> _requestRide() async {
    final client = Supabase.instance.client;
    if (pickupCoordinates == null) { await _searchPickup(); }
    if (!mounted || pickupCoordinates == null) return;
    if (destinationCoordinates == null) { await _searchDestination(); }
    if (!mounted || destinationCoordinates == null) return;

    if (client.auth.currentUser == null) {
      await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const CustomerAuthPage()));
      if (!mounted || client.auth.currentUser == null) {
        _message('Sign in with Google to request a ride. You can continue exploring without signing in.');
        return;
      }
    }
    if (fareQuote?['enabled'] != true) {
      _message(fareQuote?['message']?.toString() ?? 'Ride service is not ready in this area yet.');
      return;
    }

    setState(() => requestingRide = true);
    try {
      final currentUser = client.auth.currentUser;
      if (currentUser == null) return;
      final requestId = await client.rpc('create_customer_ride', params: {
        'p_pickup_label': pickupController.text.trim(),
        'p_pickup_latitude': pickupCoordinates![1],
        'p_pickup_longitude': pickupCoordinates![0],
        'p_destination_label': destinationController.text.trim(),
        'p_destination_latitude': destinationCoordinates![1],
        'p_destination_longitude': destinationCoordinates![0],
        'p_idempotency_key': 'ride-' + DateTime.now().microsecondsSinceEpoch.toString() + '-' + currentUser.id,
        'p_area_code': 'DEFAULT',
        'p_vehicle_type': vehicleType,
      });
      if (!mounted) return;
      _message('Ride requested. Request ID: ' + requestId.toString().substring(0, 8) + '. Fare is recalculated by Alteo before the request is saved.');
    } catch (e) {
      if (mounted) _message('Could not request this ride. Check service availability, pricing and driver coverage. ' + e.toString());
    } finally {
      if (mounted) setState(() => requestingRide = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final anyCoordinates = pickupCoordinates != null || destinationCoordinates != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Book a ride', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(tooltip: 'Use current location', onPressed: locating ? null : _useCurrentLocation, icon: const Icon(Icons.my_location_rounded)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 26),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF155C4B), Color(0xFF3C9875)]),
              borderRadius: BorderRadius.circular(23),
            ),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('YOUR NEXT TRIP, SIMPLIFIED', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.3)),
              SizedBox(height: 8),
              Text('Where to?', style: TextStyle(fontSize: 27, color: Colors.white, fontWeight: FontWeight.w900)),
              SizedBox(height: 5),
              Text('Set your pickup, search a destination and compare ride options.', style: TextStyle(color: Colors.white, height: 1.4)),
            ]),
          ),
          const SizedBox(height: 17),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE2E9E5))),
            child: Column(children: [
              Row(children: [
                Container(width: 36, height: 36, decoration: BoxDecoration(color: const Color(0xFFE3F4E9), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.my_location_rounded, color: Color(0xFF176B57))),
                const SizedBox(width: 10),
                Expanded(child: TextField(
                  controller: pickupController,
                  onChanged: (_) => setState(() { pickupCoordinates = null; fareQuote = null; }),
                  onSubmitted: (_) => _searchPickup(),
                  decoration: const InputDecoration(labelText: 'Pickup location', hintText: 'Enter pickup or use current location', border: InputBorder.none),
                )),
                IconButton(tooltip: 'Search pickup', onPressed: searchingPickup ? null : _searchPickup, icon: searchingPickup ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search_rounded)),
              ]),
              const Padding(padding: EdgeInsets.only(left: 46), child: Divider(height: 5)),
              Row(children: [
                Container(width: 36, height: 36, decoration: BoxDecoration(color: const Color(0xFFFFE9D9), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.location_on_rounded, color: Color(0xFFB65B24))),
                const SizedBox(width: 10),
                Expanded(child: TextField(
                  controller: destinationController,
                  onChanged: (_) => setState(() { destinationCoordinates = null; fareQuote = null; }),
                  onSubmitted: (_) => _searchDestination(),
                  decoration: const InputDecoration(labelText: 'Where to?', hintText: 'Search destination or landmark', border: InputBorder.none),
                )),
                IconButton(tooltip: 'Search destination', onPressed: searchingDestination ? null : _searchDestination, icon: searchingDestination ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search_rounded)),
              ]),
            ]),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: locating ? null : _useCurrentLocation,
            icon: locating ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.gps_fixed_rounded),
            label: const Text('Use current location for pickup'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), alignment: Alignment.centerLeft),
          ),
          const SizedBox(height: 16),
          if (anyCoordinates) _mapPreview() else _mapPlaceholder(),
          const SizedBox(height: 22),
          const Text('Choose your ride', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _vehicleCard('bike', 'Bike', Icons.two_wheeler_rounded, 'Solo travel')),
            const SizedBox(width: 9),
            Expanded(child: _vehicleCard('auto', 'Auto', Icons.electric_rickshaw_rounded, 'Everyday ride')),
            const SizedBox(width: 9),
            Expanded(child: _vehicleCard('car', 'Car', Icons.directions_car_filled_rounded, 'More comfort')),
          ]),
          const SizedBox(height: 14),
          _fareCard(),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: requestingRide || locating || searchingPickup || searchingDestination || fareQuote?['enabled'] != true ? null : _requestRide,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), backgroundColor: const Color(0xFF176B57)),
            child: Text(requestingRide ? 'Requesting ride…' : 'Confirm ' + _vehicleLabel(vehicleType)),
          ),
          const SizedBox(height: 9),
          const Text('Location is used only after permission is granted. Ride creation and fare calculation are validated by the Alteo backend.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Color(0xFF68736D), height: 1.45)),
        ],
      ),
    );
  }

  String _vehicleLabel(String type) => type == 'bike' ? 'bike ride' : type == 'auto' ? 'auto ride' : 'car ride';

  Widget _vehicleCard(String type, String title, IconData icon, String subtitle) {
    final selected = vehicleType == type;
    final enabled = fareQuote?['enabled'] == true;
    final fareMinor = (fareQuote?['fare_minor'] as num?)?.toInt();
    return InkWell(
      onTap: () async {
        setState(() { vehicleType = type; fareQuote = null; });
        await _refreshQuote();
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE0F2E9) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? const Color(0xFF176B57) : const Color(0xFFE2E9E5), width: selected ? 1.7 : 1),
        ),
        child: Column(children: [
          Icon(icon, color: const Color(0xFF176B57), size: 29),
          const SizedBox(height: 7),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Color(0xFF68736D))),
          const SizedBox(height: 5),
          Text(selected && enabled && fareMinor != null ? '₹' + (fareMinor / 100).toStringAsFixed(0) : 'Estimate after route', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: selected && enabled ? const Color(0xFF176B57) : const Color(0xFF68736D))),
        ]),
      ),
    );
  }

  Widget _fareCard() {
    final quote = fareQuote;
    if (quote == null) {
      return Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: const Color(0xFFF3F7F4), borderRadius: BorderRadius.circular(16)),
        child: const Row(children: [
          Icon(Icons.receipt_long_rounded, color: Color(0xFF176B57)),
          SizedBox(width: 10),
          Expanded(child: Text('Choose pickup and destination to calculate an estimated fare.', style: TextStyle(color: Color(0xFF68736D), height: 1.4))),
        ]),
      );
    }
    if (quote['enabled'] != true) {
      return Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: const Color(0xFFFFF4E5), borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFF9A5C13)),
          const SizedBox(width: 10),
          Expanded(child: Text(quote['message']?.toString() ?? 'Ride pricing is not configured yet.', style: const TextStyle(height: 1.4))),
        ]),
      );
    }
    final distance = ((quote['estimated_distance_m'] as num?)?.toDouble() ?? 0) / 1000;
    final fare = ((quote['fare_minor'] as num?)?.toInt() ?? 0) / 100;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFE3F4E9), borderRadius: BorderRadius.circular(17)),
      child: Row(children: [
        const Icon(Icons.verified_outlined, color: Color(0xFF176B57), size: 28),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Estimated fare', style: TextStyle(color: Color(0xFF365D50))),
          Text('₹' + fare.toStringAsFixed(0), style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
          Text('Approx. ' + distance.toStringAsFixed(1) + ' km · final fare verified by Alteo', style: const TextStyle(fontSize: 11, color: Color(0xFF365D50))),
        ])),
      ]),
    );
  }

  Widget _mapPreview() {
    final points = <LatLng>[];
    if (pickupCoordinates != null) points.add(LatLng(pickupCoordinates![1], pickupCoordinates![0]));
    if (destinationCoordinates != null) points.add(LatLng(destinationCoordinates![1], destinationCoordinates![0]));
    final center = points.first;
    final markers = <Marker>[];
    if (pickupCoordinates != null) {
      markers.add(Marker(point: LatLng(pickupCoordinates![1], pickupCoordinates![0]), width: 42, height: 42, child: const Icon(Icons.trip_origin_rounded, color: Color(0xFF176B57), size: 32)));
    }
    if (destinationCoordinates != null) {
      markers.add(Marker(point: LatLng(destinationCoordinates![1], destinationCoordinates![0]), width: 42, height: 42, child: const Icon(Icons.location_on_rounded, color: Color(0xFFC45E27), size: 36)));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(19),
      child: SizedBox(
        height: 190,
        child: FlutterMap(
          options: MapOptions(initialCenter: center, initialZoom: 13),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.alteo.customer'),
            MarkerLayer(markers: markers),
          ],
        ),
      ),
    );
  }

  Widget _mapPlaceholder() => Container(
    height: 145,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: const Color(0xFFEAF2ED), borderRadius: BorderRadius.circular(19)),
    child: const Row(children: [
      Icon(Icons.map_outlined, size: 42, color: Color(0xFF176B57)),
      SizedBox(width: 14),
      Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Your route preview', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        SizedBox(height: 5),
        Text('Select a pickup and destination to see both points on the map.', style: TextStyle(color: Color(0xFF68736D), height: 1.4)),
      ])),
    ]),
  );
}
