import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/mapbox_service.dart';

class CustomerLiveTrackingPage extends StatefulWidget {
  const CustomerLiveTrackingPage({
    super.key,
    required this.entityType,
    required this.entityId,
  });

  final String entityType; // ride, order, parcel
  final String entityId;

  @override
  State<CustomerLiveTrackingPage> createState() => _CustomerLiveTrackingPageState();
}

class _CustomerLiveTrackingPageState extends State<CustomerLiveTrackingPage> {
  Timer? _poller;
  Map<String, dynamic>? _snapshot;
  String? _error;
  bool _loading = true;
  bool _requestInFlight = false;
  bool _routeInFlight = false;
  DateTime? _lastRouteAt;
  String? _lastRouteKey;
  double? _routeDurationSeconds;
  double? _routeDistanceMeters;
  bool _routeIsPartnerToStop = false;
  List<LatLng> _routePoints = <LatLng>[];

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSnapshot());
    _poller = Timer.periodic(const Duration(seconds: 12), (_) {
      unawaited(_loadSnapshot(silent: true));
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  double? _number(String key) => (_snapshot?[key] as num?)?.toDouble();
  String _statusLabel(dynamic value) => (value?.toString() ?? 'pending').replaceAll('_', ' ');

  Future<void> _loadSnapshot({bool silent = false}) async {
    if (_requestInFlight) return;
    _requestInFlight = true;
    if (!silent && mounted) setState(() { _loading = true; _error = null; });
    try {
      final response = await _client.rpc('customer_tracking_snapshot', params: {
        'p_entity_type': widget.entityType,
        'p_entity_id': widget.entityId,
      }).timeout(const Duration(seconds: 12));
      final result = Map<String, dynamic>.from(response as Map);
      if (!mounted) return;
      setState(() {
        _snapshot = result;
        _loading = false;
        _error = null;
      });
      await _maybeLoadRoadRoute(result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent || _snapshot == null) {
          _error = 'Tracking could not be loaded. Check your connection and retry.';
        }
      });
    } finally {
      _requestInFlight = false;
    }
  }

  Future<void> _maybeLoadRoadRoute(Map<String, dynamic> data) async {
    if (!MapboxService.isConfigured || _routeInFlight) return;
    final partnerLat = (data['partner_latitude'] as num?)?.toDouble();
    final partnerLon = (data['partner_longitude'] as num?)?.toDouble();
    final pickupLat = (data['pickup_latitude'] as num?)?.toDouble();
    final pickupLon = (data['pickup_longitude'] as num?)?.toDouble();
    final destinationLat = (data['destination_latitude'] as num?)?.toDouble();
    final destinationLon = (data['destination_longitude'] as num?)?.toDouble();
    if (pickupLat == null || pickupLon == null || destinationLat == null || destinationLon == null) return;

    final nextStop = data['next_stop']?.toString() ?? 'pickup';
    final hasLivePartnerLocation = data['location_available'] == true && partnerLat != null && partnerLon != null;
    // When no partner GPS is available, show the planned pickup-to-destination
    // route and trip duration; once GPS arrives, switch to partner-to-next-stop ETA.
    final startLat = hasLivePartnerLocation ? partnerLat : pickupLat;
    final startLon = hasLivePartnerLocation ? partnerLon : pickupLon;
    final targetLat = hasLivePartnerLocation
        ? (nextStop == 'destination' ? destinationLat : pickupLat)
        : destinationLat;
    final targetLon = hasLivePartnerLocation
        ? (nextStop == 'destination' ? destinationLon : pickupLon)
        : destinationLon;
    final routeKey = [
      startLat.toStringAsFixed(3), startLon.toStringAsFixed(3),
      targetLat.toStringAsFixed(3), targetLon.toStringAsFixed(3),
      hasLivePartnerLocation ? 'live-$nextStop' : 'trip',
    ].join(':');
    final now = DateTime.now();
    if (_lastRouteKey == routeKey && _lastRouteAt != null &&
        now.difference(_lastRouteAt!) < const Duration(seconds: 40)) {
      return;
    }

    _routeInFlight = true;
    try {
      final route = await MapboxService.directions(
        startLongitude: startLon,
        startLatitude: startLat,
        endLongitude: targetLon,
        endLatitude: targetLat,
        profile: 'driving',
      );
      if (!mounted || route == null) return;
      setState(() {
        _routePoints = route.coordinates.map((p) => LatLng(p[1], p[0])).toList();
        _routeDurationSeconds = route.durationSeconds;
        _routeDistanceMeters = route.distanceMeters;
        _routeIsPartnerToStop = hasLivePartnerLocation;
      });
      _lastRouteKey = routeKey;
      _lastRouteAt = now;
    } finally {
      _routeInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.entityType == 'ride'
        ? 'Ride tracking'
        : widget.entityType == 'parcel'
          ? 'Parcel tracking'
          : 'Delivery tracking';
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            tooltip: 'Refresh tracking',
            onPressed: _loading ? null : () => _loadSnapshot(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading && _snapshot == null
        ? const Center(child: CircularProgressIndicator())
        : _error != null && _snapshot == null
          ? Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.cloud_off_rounded, size: 42, color: Color(0xFF176B57)),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 14),
                FilledButton.icon(onPressed: () => _loadSnapshot(), icon: const Icon(Icons.refresh_rounded), label: const Text('Try again')),
              ]),
            ))
          : _trackingBody(),
    );
  }

  Widget _trackingBody() {
    final data = _snapshot ?? <String, dynamic>{};
    final status = _statusLabel(data['status']);
    final isTerminal = const {'completed', 'delivered', 'cancelled', 'rejected'}.contains(data['status']?.toString());
    final partnerLat = _number('partner_latitude');
    final partnerLon = _number('partner_longitude');
    final pickupLat = _number('pickup_latitude');
    final pickupLon = _number('pickup_longitude');
    final destinationLat = _number('destination_latitude');
    final destinationLon = _number('destination_longitude');
    final locationAvailable = data['location_available'] == true && partnerLat != null && partnerLon != null;
    final trackingAvailable = data['tracking_available'] == true;
    final rawEtaSeconds = (data['eta_to_next_stop_s'] as num?)?.toInt();
    final etaSeconds = _routeIsPartnerToStop ? _routeDurationSeconds?.ceil() : rawEtaSeconds;
    final rawTripSeconds = (data['estimated_trip_duration_s'] as num?)?.toInt();
    final tripSeconds = !_routeIsPartnerToStop ? (_routeDurationSeconds?.ceil() ?? rawTripSeconds) : rawTripSeconds;
    final rawDistanceMeters = (data['estimated_distance_m'] as num?)?.toInt();
    final distanceMeters = !_routeIsPartnerToStop ? (_routeDistanceMeters?.round() ?? rawDistanceMeters) : rawDistanceMeters;
    final nextStop = data['next_stop']?.toString() ?? 'pickup';

    final markers = <Marker>[];
    if (pickupLat != null && pickupLon != null) {
      markers.add(Marker(
        point: LatLng(pickupLat, pickupLon), width: 38, height: 42,
        child: const Icon(Icons.trip_origin_rounded, color: Color(0xFF176B57), size: 30),
      ));
    }
    if (destinationLat != null && destinationLon != null) {
      markers.add(Marker(
        point: LatLng(destinationLat, destinationLon), width: 38, height: 42,
        child: const Icon(Icons.location_on_rounded, color: Color(0xFFC45E27), size: 34),
      ));
    }
    if (locationAvailable) {
      markers.add(Marker(
        point: LatLng(partnerLat, partnerLon), width: 46, height: 46,
        child: Container(
          decoration: BoxDecoration(color: const Color(0x332168C7), shape: BoxShape.circle, border: Border.all(color: const Color(0xFF2168C7), width: 2)),
          child: const Icon(Icons.my_location_rounded, color: Color(0xFF2168C7), size: 26),
        ),
      ));
    }
    final fallbackLine = <LatLng>[];
    if (_routePoints.length < 2) {
      if (locationAvailable) {
        final tLat = nextStop == 'destination' ? destinationLat : pickupLat;
        final tLon = nextStop == 'destination' ? destinationLon : pickupLon;
        if (tLat != null && tLon != null) fallbackLine.addAll([LatLng(partnerLat!, partnerLon!), LatLng(tLat, tLon)]);
      } else if (pickupLat != null && pickupLon != null && destinationLat != null && destinationLon != null) {
        fallbackLine.addAll([LatLng(pickupLat, pickupLon), LatLng(destinationLat, destinationLon)]);
      }
    }
    final focus = locationAvailable
        ? LatLng(partnerLat!, partnerLon!)
        : pickupLat != null && pickupLon != null
          ? LatLng(pickupLat, pickupLon)
          : destinationLat != null && destinationLon != null
            ? LatLng(destinationLat, destinationLon)
            : const LatLng(20.5937, 78.9629);
    final tileUrl = MapboxService.isConfigured
        ? 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token=${MapboxService.publicToken}'
        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

    return RefreshIndicator(
      onRefresh: () => _loadSnapshot(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFFE1F2E9), borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              const Icon(Icons.local_shipping_rounded, size: 30, color: Color(0xFF176B57)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('CURRENT STATUS', style: TextStyle(fontSize: 10, letterSpacing: 1.1, fontWeight: FontWeight.w900, color: Color(0xFF68736D))),
                const SizedBox(height: 4),
                Text(status.toUpperCase(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF176B57))),
                if ((data['message']?.toString() ?? '').isNotEmpty)
                  Text(data['message'].toString(), style: const TextStyle(fontSize: 12, height: 1.4, color: Color(0xFF365D50))),
              ])),
            ]),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: 320,
              child: FlutterMap(
                options: MapOptions(initialCenter: focus, initialZoom: locationAvailable ? 14 : pickupLat == null ? 4.4 : 12.5),
                children: [
                  TileLayer(
                    urlTemplate: tileUrl,
                    fallbackUrl: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.alteo.customer',
                    maxZoom: 19,
                  ),
                  if (_routePoints.length >= 2)
                    PolylineLayer(polylines: [Polyline(points: _routePoints, strokeWidth: 4, color: const Color(0xFF176B57))])
                  else if (fallbackLine.length >= 2)
                    PolylineLayer(polylines: [Polyline(points: fallbackLine, strokeWidth: 3, color: const Color(0xFF176B57))]),
                  if (markers.isNotEmpty) MarkerLayer(markers: markers),
                  RichAttributionWidget(attributions: [
                    if (MapboxService.isConfigured) const TextSourceAttribution('© Mapbox'),
                    const TextSourceAttribution('© OpenStreetMap contributors'),
                  ]),
                ],
              ),
            ),
          ),
          if (!MapboxService.isConfigured || MapboxService.lastError != null) ...[
            const SizedBox(height: 8),
            Text(
              !MapboxService.isConfigured ? MapboxService.configurationMessage : (MapboxService.lastError ?? ''),
              style: const TextStyle(color: Color(0xFF8A5A16), fontSize: 12, height: 1.4),
            ),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _metric('ESTIMATED DISTANCE', distanceMeters == null ? '—' : '${(distanceMeters / 1000).toStringAsFixed(1)} km')),
            const SizedBox(width: 9),
            Expanded(child: _metric('ESTIMATED TRIP TIME', tripSeconds == null ? '—' : _formatDuration(tripSeconds))),
          ]),
          const SizedBox(height: 9),
          Row(children: [
            Expanded(child: _metric('ETA TO ${nextStop == 'destination' ? 'DESTINATION' : 'PICKUP'}', isTerminal ? 'Trip complete' : etaSeconds == null ? (trackingAvailable ? 'Waiting for location' : 'Awaiting assignment') : _formatDuration(etaSeconds))),
            const SizedBox(width: 9),
            Expanded(child: _metric('LOCATION STATUS', locationAvailable ? 'Live' : 'Waiting')),
          ]),
          const SizedBox(height: 12),
          _addressCard('Pickup', data['pickup_label']?.toString() ?? 'Pickup location', Icons.trip_origin_rounded),
          const SizedBox(height: 8),
          _addressCard('Destination', data['destination_label']?.toString() ?? 'Destination', Icons.location_on_rounded),
          if (!trackingAvailable) ...[
            const SizedBox(height: 12),
            _infoCard('Partner not assigned yet', 'The status and trip estimate are available, but live map tracking starts once dispatch assigns a driver or delivery partner.'),
          ] else if (!locationAvailable) ...[
            const SizedBox(height: 12),
            _infoCard('Waiting for live GPS', 'The assigned partner must be online and share a recent location. The map refreshes automatically about every 12 seconds.'),
          ],
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 8),
          const Text('Estimated times are approximate. A road-based route/ETA is shown only when Mapbox Directions is configured and can resolve the route.', style: TextStyle(fontSize: 11, color: Color(0xFF68736D), height: 1.4)),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFE2E9E5))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 9, letterSpacing: .8, fontWeight: FontWeight.w900, color: Color(0xFF68736D))),
      const SizedBox(height: 6),
      Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF176B57))),
    ]),
  );

  Widget _addressCard(String title, String value, IconData icon) => Card(
    elevation: 0,
    child: ListTile(
      leading: CircleAvatar(backgroundColor: const Color(0xFFE1F2E9), child: Icon(icon, color: const Color(0xFF176B57))),
      title: Text(title, style: const TextStyle(fontSize: 12, color: Color(0xFF68736D))),
      subtitle: Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
    ),
  );

  Widget _infoCard(String title, String detail) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: const Color(0xFFFFF4E5), borderRadius: BorderRadius.circular(15)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF8A5A16))),
      const SizedBox(height: 5),
      Text(detail, style: const TextStyle(fontSize: 12, height: 1.4)),
    ]),
  );

  String _formatDuration(int seconds) {
    final minutes = (seconds / 60).ceil();
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final remain = minutes % 60;
    return remain == 0 ? '$hours hr' : '$hours hr $remain min';
  }
}
