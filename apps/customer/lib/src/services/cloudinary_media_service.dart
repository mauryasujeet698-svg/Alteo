import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Uploads require an authenticated backend signature. Never ship the
/// Cloudinary API secret in a mobile app.
class CloudinaryMediaService {
  CloudinaryMediaService({
    required this.cloudName,
    required SupabaseClient supabase,
    http.Client? httpClient,
  })  : _supabase = supabase,
        _http = httpClient ?? http.Client();

  final String cloudName;
  final SupabaseClient _supabase;
  final http.Client _http;

  Future<String> uploadImageBytes({
    required List<int> bytes,
    required String fileName,
    required String folder,
  }) async {
    if (cloudName.trim().isEmpty) throw StateError('CLOUDINARY_CLOUD_NAME is missing.');
    if (_supabase.auth.currentSession == null) throw StateError('Sign in before uploading.');

    final signed = await _supabase.functions.invoke(
      'cloudinary-upload-signature',
      body: {'folder': folder},
    );
    if (signed.status < 200 || signed.status >= 300 ||
        signed.data is! Map<String, dynamic>) {
      throw StateError('Could not obtain a secure upload signature.');
    }

    final data = signed.data as Map<String, dynamic>;
    final timestamp = data['timestamp'];
    final signature = data['signature'];
    final apiKey = data['apiKey'];
    final signedFolder = data['folder'];
    if (timestamp == null || signature == null || apiKey == null || signedFolder == null) {
      throw StateError('Upload signature response is incomplete.');
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.https('api.cloudinary.com', '/v1_1/$cloudName/image/upload'),
    )
      ..fields['api_key'] = apiKey.toString()
      ..fields['timestamp'] = timestamp.toString()
      ..fields['signature'] = signature.toString()
      ..fields['folder'] = signedFolder.toString()
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));

    final streamed = await _http.send(request);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Cloudinary upload failed (${response.statusCode}).');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['secure_url'] is! String) {
      throw StateError('Invalid Cloudinary response.');
    }
    return decoded['secure_url'] as String;
  }
}
