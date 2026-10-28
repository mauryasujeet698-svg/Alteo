import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../services/customer_location_service.dart';
import '../../services/mapbox_service.dart';

class CustomerLocationPickerPage extends StatefulWidget {
  const CustomerLocationPickerPage({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.initialAddress,
  });

  final double? initialLatitude;
  final double? initialLongitude;
  final String? initialAddress;

  @override
  State<CustomerLocationPickerPage> createState() => _CustomerLocationPickerPageState();
}

class _CustomerLocationPickerPageState extends State<CustomerLocationPickerPage> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  LatLng _selected = const LatLng(25.9804, 81.5000);
  Map<String, dynamic>? _details;
  bool _resolving = false;
  bool _searching = false;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _selected = LatLng(widget.initialLatitude!, widget.initialLongitude!);
      unawaited(_resolve(_selected));
    } else if ((widget.initialAddress ?? '').trim().isNotEmpty) {
      _searchController.text = widget.initialAddress!.trim();
      unawaited(_search(widget.initialAddress!.trim(), quiet: true));
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _resolve(LatLng point) async {
    if (!mounted) return;
    setState(() {
      _selected = point;
      _resolving = true;
      _details = null;
    });
    try {
      final details = await CustomerLocationService.resolveCoordinates(point.latitude, point.longitude);
      if (!mounted) return;
      setState(() {
        _details = details;
        _resolving = false;
      });
      _searchController.text = details['formatted_address']?.toString() ?? '';
    } catch (_) {
      if (mounted) setState(() => _resolving = false);
    }
  }

  Future<void> _search(String query, {bool quiet = false}) async {
    final value = query.trim();
    if (value.length < 3) {
      if (!quiet) _message('Enter an address, locality, landmark or PIN code.');
      return;
    }
    setState(() => _searching = true);
    try {
      final details = await CustomerLocationService.searchAddress(value);
      if (details == null) {
        if (!quiet) _message('We could not find that location. Try a nearby landmark or move the pin on the map.');
        return;
      }
      final lat = (details['latitude'] as num).toDouble();
      final lon = (details['longitude'] as num).toDouble();
      if (!mounted) return;
      setState(() {
        _selected = LatLng(lat, lon);
        _details = details;
      });
      if (_mapReady) _mapController.move(_selected, 15);
      _searchController.text = details['formatted_address']?.toString() ?? value;
    } catch (_) {
      if (!quiet) _message('Location search is unavailable right now. Move the map pin to choose the exact place.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _message('Turn on Location services in your phone settings, then try again.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _message('Allow location access in your phone settings or search for an address instead.');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      final point = LatLng(position.latitude, position.longitude);
      await _resolve(point);
      if (_mapReady) _mapController.move(point, 16);
    } catch (_) {
      _message('We could not detect your location. Search for an address or move the map pin instead.');
    }
  }

  void _message(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Map<String, dynamic> _selection() {
    final details = Map<String, dynamic>.from(_details ?? <String, dynamic>{});
    details['latitude'] = _selected.latitude;
    details['longitude'] = _selected.longitude;
    details['formatted_address'] = (details['formatted_address']?.toString().trim().isNotEmpty ?? false)
        ? details['formatted_address']
        : 'Selected map location';
    details['display_address'] = (details['display_address']?.toString().trim().isNotEmpty ?? false)
        ? details['display_address']
        : details['formatted_address'];
    return details;
  }

  @override
  Widget build(BuildContext context) {
    final tileUrl = MapboxService.isConfigured
        ? 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token=${MapboxService.publicToken}'
        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose exact location', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            tooltip: 'Use my location',
            onPressed: _useCurrentLocation,
            icon: const Icon(Icons.my_location_rounded),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onSubmitted: (value) => _search(value),
            decoration: InputDecoration(
              hintText: 'Search house, street, locality or PIN code',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                tooltip: 'Search address',
                onPressed: _searching ? null : () => _search(_searchController.text),
                icon: _searching
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.arrow_forward_rounded),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
        Expanded(
          child: Stack(children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _selected,
                initialZoom: widget.initialLatitude == null ? 6.0 : 15.0,
                onMapReady: () => _mapReady = true,
                onTap: (_, point) => _resolve(point),
              ),
              children: [
                TileLayer(
                  urlTemplate: tileUrl,
                  fallbackUrl: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.alteo.customer',
                  maxZoom: 19,
                ),
                MarkerLayer(markers: [
                  Marker(
                    point: _selected,
                    width: 52,
                    height: 56,
                    child: const Icon(Icons.location_pin, color: Color(0xFF176B57), size: 48),
                  ),
                ]),
                RichAttributionWidget(attributions: [
                  if (MapboxService.isConfigured) const TextSourceAttribution('© Mapbox'),
                  const TextSourceAttribution('© OpenStreetMap contributors'),
                ]),
              ],
            ),
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Container(
                decoration: BoxDecoration(color: Colors.white.withOpacity(.96), borderRadius: BorderRadius.circular(14), boxShadow: const [BoxShadow(color: Color(0x18000000), blurRadius: 12)]),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  const Icon(Icons.touch_app_rounded, color: Color(0xFF176B57)),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Tap the map to place the pin exactly at the delivery point.', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                ]),
              ),
            ),
          ]),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, border: Border(top: BorderSide(color: Theme.of(context).dividerColor.withOpacity(.35)))),
          child: SafeArea(
            top: false,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const Icon(Icons.location_on_rounded, color: Color(0xFF176B57)),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  _resolving ? 'Getting address details…' : (_details?['display_address']?.toString() ?? 'Selected map location'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                )),
                if (_resolving) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ]),
              if ((_details?['formatted_address']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 32),
                  child: Text(_details!['formatted_address'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, height: 1.35, color: Color(0xFF68736D))),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _resolving ? null : () => Navigator.of(context).pop<Map<String, dynamic>>(_selection()),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Confirm this location'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
