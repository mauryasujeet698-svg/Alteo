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
  final MapController mapController = MapController();
  List<double>? currentCoordinates;
  List<double>? pickupCoordinates;
  List<double>? destinationCoordinates;
  String vehicleType = 'bike';
  bool locating = false;
  bool searchingPickup = false;
  bool searchingDestination = false;
  bool requestingRide = false;
  Map<String, dynamic>? fareQuote;
  MapboxRouteResult? routeResult;
  List<LatLng> routeCoordinates = <LatLng>[];
  bool calculatingRoute = false;

  @override
  void initState() {
    super.initState();
    if (widget.enableBackendQueries) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _useCurrentLocation(silent: true);
      });
    }
  }

  @override
  void dispose() {
    pickupController.dispose();
    destinationController.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _useCurrentLocation({bool silent = false}) async {
    setState(() => locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!silent) _message('Turn on Location on your phone to use your current pickup point.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (!silent) _message('Location permission is needed for current pickup. You can enter a pickup address manually instead.');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 12)),
      );
      final address = await MapboxService.reverseGeocode(position.longitude, position.latitude);
      if (!mounted) return;
      setState(() {
        currentCoordinates = [position.longitude, position.latitude];
        pickupCoordinates = [position.longitude, position.latitude];
        pickupController.text = address ?? 'Current location';
      });
      await _refreshQuote();
      if (address == null && MapboxService.isConfigured && MapboxService.lastError != null && !silent) {
        _message(MapboxService.lastError!);
      }
    } catch (_) {
      if (!silent) _message('Could not get your current location. Try again or enter a pickup address.');
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
      if (coords == null) { _message(MapboxService.lastError ?? 'Pickup not found. Try a fuller address or nearby landmark.'); return; }
      if (!mounted) return;
      setState(() => pickupCoordinates = coords);
      try { mapController.move(LatLng(coords[1], coords[0]), 14.5); } catch (_) {}
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
      if (coords == null) { _message(MapboxService.lastError ?? 'Destination not found. Try a fuller address or nearby landmark.'); return; }
      if (!mounted) return;
      setState(() => destinationCoordinates = coords);
      try { mapController.move(LatLng((pickupCoordinates ?? coords)[1], (pickupCoordinates ?? coords)[0]), 14.5); } catch (_) {}
      await _refreshQuote();
    } finally {
      if (mounted) setState(() => searchingDestination = false);
    }
  }

  Future<void> _refreshQuote() async {
    if (!widget.enableBackendQueries) { if (mounted) setState(() => fareQuote = {'enabled': false, 'message': 'Preview mode: live ride prices load when backend access is enabled.'}); return; }
    if (pickupCoordinates == null || destinationCoordinates == null) {
      if (mounted) setState(() => fareQuote = null);
      await _refreshRoute();
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
      await _refreshRoute();
    } catch (_) {
      if (mounted) setState(() => fareQuote = {
        'enabled': false,
        'message': 'Fare estimate is unavailable. Check that ride pricing and service availability are configured in Admin.',
      });
      await _refreshRoute();
    }
  }

  Future<void> _refreshRoute() async {
    final pickup = pickupCoordinates;
    final destination = destinationCoordinates;
    if (pickup == null || destination == null) {
      if (mounted) setState(() { routeResult = null; routeCoordinates = <LatLng>[]; calculatingRoute = false; });
      return;
    }
    if (!MapboxService.isConfigured) {
      if (mounted) setState(() { routeResult = null; routeCoordinates = <LatLng>[]; calculatingRoute = false; });
      return;
    }
    if (mounted) setState(() => calculatingRoute = true);
    final route = await MapboxService.directions(
      startLongitude: pickup[0],
      startLatitude: pickup[1],
      endLongitude: destination[0],
      endLatitude: destination[1],
      profile: 'driving',
    );
    if (!mounted) return;
    setState(() {
      routeResult = route;
      routeCoordinates = route?.coordinates.map((point) => LatLng(point[1], point[0])).toList() ?? <LatLng>[];
      calculatingRoute = false;
    });
    if (route == null && MapboxService.lastError != null) {
      _message(MapboxService.lastError!);
    }
  }

  Widget _mapboxStatusMessage() {
    final message = !MapboxService.isConfigured
        ? MapboxService.configurationMessage
        : MapboxService.lastError;
    if (message == null || message.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFF0D9B3)),
      ),
      child: Row(children: [
        const Icon(Icons.info_outline_rounded, color: Color(0xFF9A5C13)),
        const SizedBox(width: 9),
        Expanded(child: Text(message, style: const TextStyle(fontSize: 12, height: 1.4, color: Color(0xFF75450D)))),
      ]),
    );
  }

  Widget _etaSummary() {
    final pickup = pickupCoordinates;
    final destination = destinationCoordinates;
    if (pickup == null || destination == null) return const SizedBox.shrink();
    final quoteDistance = (fareQuote?['estimated_distance_m'] as num?)?.toDouble();
    final distanceMeters = routeResult?.distanceMeters ?? quoteDistance ??
      MapboxService.straightLineDistanceMeters(pickup[1], pickup[0], destination[1], destination[0]);
    final durationSeconds = routeResult?.durationSeconds ?? (distanceMeters / 5.5) + 180;
    final minutes = (durationSeconds / 60).ceil();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFE4F4EA), borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        const Icon(Icons.schedule_rounded, color: Color(0xFF176B57), size: 26),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(calculatingRoute ? 'Calculating road ETA…' : routeResult != null ? 'Estimated travel time' : 'Approximate travel time',
            style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF176B57))),
          Text('About $minutes min · ${(distanceMeters / 1000).toStringAsFixed(1)} km',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          if (routeResult == null)
            const Text('This is a rough estimate, not a road-routed ETA.', style: TextStyle(fontSize: 11, color: Color(0xFF68736D))),
        ])),
      ]),
    );
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
      if (mounted) _message('Could not request this ride right now. Please try again or check whether rides are available in your area.');
    } finally {
      if (mounted) setState(() => requestingRide = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          _mapPreview(),
          _mapboxStatusMessage(),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE2E9E5))),
            child: Column(children: [
              Row(children: [
                Container(width: 36, height: 36, decoration: BoxDecoration(color: const Color(0xFFE3F4E9), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.my_location_rounded, color: Color(0xFF176B57))),
                const SizedBox(width: 10),
                Expanded(child: TextField(
                  controller: pickupController,
                  onChanged: (_) => setState(() { pickupCoordinates = null; fareQuote = null; routeResult = null; routeCoordinates = <LatLng>[]; }),
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
                  onChanged: (_) => setState(() { destinationCoordinates = null; fareQuote = null; routeResult = null; routeCoordinates = <LatLng>[]; }),
                  onSubmitted: (_) => _searchDestination(),
                  decoration: const InputDecoration(labelText: 'Where to?', hintText: 'Search destination or landmark', border: InputBorder.none),
                )),
                IconButton(tooltip: 'Search destination', onPressed: searchingDestination ? null : _searchDestination, icon: searchingDestination ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search_rounded)),
              ]),
            ]),
          ),
          const SizedBox(height: 18),
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
          _etaSummary(),
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
    final current = currentCoordinates;
    final pickup = pickupCoordinates;
    final destination = destinationCoordinates;
    final focus = pickup ?? current ?? destination;
    final center = focus == null ? const LatLng(20.5937, 78.9629) : LatLng(focus[1], focus[0]);
    final markers = <Marker>[];
    if (current != null) {
      markers.add(Marker(
        point: LatLng(current[1], current[0]), width: 44, height: 44,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0x331768C2), shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF1768C2), width: 2),
          ),
          child: const Center(child: Icon(Icons.my_location_rounded, color: Color(0xFF1768C2), size: 22)),
        ),
      ));
    }
    if (pickup != null) {
      markers.add(Marker(point: LatLng(pickup[1], pickup[0]), width: 38, height: 42,
        child: const Icon(Icons.trip_origin_rounded, color: Color(0xFF176B57), size: 30)));
    }
    if (destination != null) {
      markers.add(Marker(point: LatLng(destination[1], destination[0]), width: 38, height: 42,
        child: const Icon(Icons.location_on_rounded, color: Color(0xFFC45E27), size: 34)));
    }
    final tileUrl = MapboxService.isConfigured
      ? 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token=' + MapboxService.publicToken
      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        height: 285,
        child: Stack(fit: StackFit.expand, children: [
          FlutterMap(
            mapController: mapController,
            options: MapOptions(initialCenter: center, initialZoom: focus == null ? 4.3 : 14.5),
            children: [
              TileLayer(urlTemplate: tileUrl, fallbackUrl: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.alteo.customer'),
              if (routeCoordinates.length >= 2)
                PolylineLayer(polylines: [
                  Polyline(points: routeCoordinates, strokeWidth: 4, color: const Color(0xFF176B57)),
                ])
              else if (pickup != null && destination != null)
                PolylineLayer(polylines: [
                  Polyline(points: [LatLng(pickup[1], pickup[0]), LatLng(destination[1], destination[0])], strokeWidth: 3, color: const Color(0xFF7CA89A)),
                ]),
              if (markers.isNotEmpty) MarkerLayer(markers: markers),
              RichAttributionWidget(attributions: [
                if (MapboxService.isConfigured) const TextSourceAttribution('© Mapbox'),
                const TextSourceAttribution('© OpenStreetMap contributors'),
              ]),
            ],
          ),
          Positioned(
            left: 12, top: 12, right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .96),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [BoxShadow(color: Color(0x18000000), blurRadius: 12, offset: Offset(0, 3))],
              ),
              child: Row(children: [
                const Icon(Icons.location_on_rounded, color: Color(0xFF176B57)),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('YOUR PICKUP AREA', style: TextStyle(fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.w900, color: Color(0xFF68736D))),
                  Text(current != null ? 'Current location detected' : 'Locate yourself on the map', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                ])),
                IconButton(
                  tooltip: 'Use current location',
                  onPressed: locating ? null : () => _useCurrentLocation(),
                  icon: locating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location_rounded),
                ),
              ]),
            ),
          ),
          Positioned(
            right: 10, bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .92), borderRadius: BorderRadius.circular(8)),
              child: Text(!MapboxService.isConfigured ? 'Map preview · token missing' : routeResult != null ? 'Mapbox road route' : 'Mapbox enabled', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
      ),
    );
  }

}
