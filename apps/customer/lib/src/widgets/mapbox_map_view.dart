import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../services/mapbox_service.dart';

/// Reusable Mapbox surface. Coordinates are supplied by the calling feature;
/// this widget does not start GPS tracking or request location permission.
class MapboxMapView extends StatelessWidget {
  const MapboxMapView({
    super.key,
    required this.latitude,
    required this.longitude,
    this.zoom = 12,
  });

  final double latitude;
  final double longitude;
  final double zoom;

  @override
  Widget build(BuildContext context) {
    if (!MapboxService.isConfigured) {
      return const Center(child: Text('Map is unavailable. Configure MAPBOX_PUBLIC_TOKEN.'));
    }
    return MapWidget(
      cameraOptions: CameraOptions(
        center: Point(coordinates: Position(longitude, latitude)),
        zoom: zoom,
      ),
    );
  }
}
