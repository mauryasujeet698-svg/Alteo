import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class CloudinaryUploadResult {
  const CloudinaryUploadResult({required this.publicId, required this.secureUrl});
  final String publicId;
  final String secureUrl;
}

/// Direct signed uploads. Cloudinary API secrets stay in the Edge Function.
class CloudinaryMediaService {
  CloudinaryMediaService({
    required this.cloudName,
    required SupabaseClient supabase,
    http.Client? httpClient,
  })  : _supabase = supabase,
        _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  static const int maxClientImageBytes = 8 * 1024 * 1024;
  final String cloudName;
  final SupabaseClient _supabase;
  final http.Client _http;
  final bool _ownsClient;

  Future<CloudinaryUploadResult> uploadImageBytes({
    required List<int> bytes,
    required String assetKind,
  }) async {
    if (cloudName.trim().isEmpty) throw StateError('CLOUDINARY_CLOUD_NAME is missing.');
    if (_supabase.auth.currentSession == null) throw StateError('Sign in before uploading.');
    if (bytes.isEmpty || bytes.length > maxClientImageBytes) {
      throw StateError('Image must be between 1 byte and 8 MB.');
    }
    final extension = _detectImageExtension(bytes);
    if (extension == null) {
      throw StateError('Only valid JPEG, PNG and WebP images are supported.');
    }
    if (!const {'profile', 'product', 'food_listing'}.contains(assetKind)) {
      throw ArgumentError.value(assetKind, 'assetKind', 'Unsupported asset type.');
    }

    final signed = await _supabase.functions.invoke(
      'cloudinary-upload-signature',
      body: {'assetKind': assetKind},
    );
    if (signed.status < 200 || signed.status >= 300 || signed.data is! Map<String, dynamic>) {
      throw StateError('Could not obtain a secure upload signature.');
    }
    final data = signed.data as Map<String, dynamic>;
    final timestamp = data['timestamp'];
    final signature = data['signature'];
    final apiKey = data['apiKey'];
    final signedFolder = data['folder'];
    final allowedFormats = data['allowedFormats'];
    if (timestamp == null ||
        signature == null ||
        apiKey == null ||
        signedFolder == null ||
        allowedFormats != 'jpg,png,webp') {
      throw StateError('Upload signature response is incomplete or invalid.');
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.https('api.cloudinary.com', '/v1_1/' + cloudName + '/image/upload'),
    )
      ..fields['api_key'] = apiKey.toString()
      ..fields['timestamp'] = timestamp.toString()
      ..fields['signature'] = signature.toString()
      ..fields['folder'] = signedFolder.toString()
      ..fields['allowed_formats'] = allowedFormats.toString()
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: 'alteo_image.' + extension,
      ));

    final streamed = await _http.send(request);
    final uploadResponse = await http.Response.fromStream(streamed);
    if (uploadResponse.statusCode < 200 || uploadResponse.statusCode >= 300) {
      throw StateError('Cloudinary upload failed (' + uploadResponse.statusCode.toString() + ').');
    }
    final decoded = jsonDecode(uploadResponse.body);
    if (decoded is! Map<String, dynamic> ||
        decoded['secure_url'] is! String ||
        decoded['public_id'] is! String) {
      throw StateError('Invalid Cloudinary response.');
    }
    final uri = Uri.tryParse(decoded['secure_url'] as String);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'res.cloudinary.com' ||
        uri.pathSegments.isEmpty ||
        uri.pathSegments.first != cloudName) {
      throw StateError('Cloudinary returned an unexpected asset URL.');
    }
    return CloudinaryUploadResult(
      publicId: decoded['public_id'] as String,
      secureUrl: uri.toString(),
    );
  }

  void close() {
    if (_ownsClient) _http.close();
  }

  String? _detectImageExtension(List<int> b) {
    if (b.length >= 3 && b[0] == 0xff && b[1] == 0xd8 && b[2] == 0xff) return 'jpg';
    if (b.length >= 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4e &&
        b[3] == 0x47 &&
        b[4] == 0x0d &&
        b[5] == 0x0a &&
        b[6] == 0x1a &&
        b[7] == 0x0a) {
      return 'png';
    }
    if (b.length >= 12 &&
        _ascii(b, 0, 4) == 'RIFF' &&
        _ascii(b, 8, 12) == 'WEBP') {
      return 'webp';
    }
    return null;
  }

  String _ascii(List<int> bytes, int start, int end) =>
      String.fromCharCodes(bytes.sublist(start, end));
}
