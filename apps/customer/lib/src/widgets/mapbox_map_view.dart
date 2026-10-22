import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/mapbox_service.dart';

/// Lightweight interactive map. Uses Mapbox raster tiles when a public token is
/// supplied; otherwise falls back to OpenStreetMap to keep the app usable.
class MapboxMapView extends StatelessWidget {
 const MapboxMapView({super.key,required this.latitude,required this.longitude,this.zoom=12});
 final double latitude,longitude,zoom;
 @override Widget build(BuildContext context){
  final template=MapboxService.isConfigured
   ? 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token=${MapboxService.publicToken}'
   : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  return ClipRRect(borderRadius:BorderRadius.circular(16),child:FlutterMap(
   options:MapOptions(initialCenter:LatLng(latitude,longitude),initialZoom:zoom),
   children:[
    TileLayer(urlTemplate:template,userAgentPackageName:'com.alteo.customer',maxZoom:19),
    MarkerLayer(markers:[Marker(point:LatLng(latitude,longitude),width:42,height:42,child:const Icon(Icons.location_pin,color:Color(0xFF176B57),size:42))]),
   ],
  ));
 }
}