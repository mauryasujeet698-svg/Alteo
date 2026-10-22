/// Lightweight map configuration. Only a public, URL-restricted Mapbox token
/// may be shipped in the client. OpenStreetMap tiles are used as a fallback.
class MapboxService {
 MapboxService._();
 static String _publicToken='';
 static void configure(String publicToken)=>_publicToken=publicToken.trim();
 static bool get isConfigured=>_publicToken.isNotEmpty;
 static String get publicToken=>_publicToken;
}