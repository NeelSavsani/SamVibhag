import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Uploads profile photos to the same Cloudinary environment used for group
/// images. Only the returned HTTPS delivery URL is stored in the user profile.
class CloudinaryAvatarService {
  static const _cloudName = 'kgtyxboo';
  static const _uploadPreset = 'samvibhag_preset';

  Future<String> upload(File image) async {
    if (!await image.exists()) {
      throw const CloudinaryAvatarUploadException('avatar_file_missing');
    }

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.https(
          'api.cloudinary.com',
          '/v1_1/$_cloudName/image/upload',
        ),
      )..fields['upload_preset'] = _uploadPreset;
      request.files.add(await http.MultipartFile.fromPath('file', image.path));

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 45),
      );
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const CloudinaryAvatarUploadException('cloudinary_upload_failed');
      }

      final decoded = jsonDecode(response.body);
      final secureUrl = decoded is Map<String, dynamic>
          ? decoded['secure_url']
          : null;
      final uri = secureUrl is String ? Uri.tryParse(secureUrl) : null;
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        throw const CloudinaryAvatarUploadException(
          'cloudinary_response_invalid',
        );
      }

      return uri.toString();
    } on CloudinaryAvatarUploadException {
      rethrow;
    } on FormatException {
      throw const CloudinaryAvatarUploadException(
        'cloudinary_response_invalid',
      );
    } on SocketException {
      throw const CloudinaryAvatarUploadException('network_unavailable');
    } on HttpException {
      throw const CloudinaryAvatarUploadException('cloudinary_upload_failed');
    } on TlsException {
      throw const CloudinaryAvatarUploadException('secure_connection_failed');
    } on Exception {
      throw const CloudinaryAvatarUploadException('cloudinary_upload_failed');
    }
  }
}

class CloudinaryAvatarUploadException implements Exception {
  const CloudinaryAvatarUploadException(this.code);

  final String code;

  @override
  String toString() => 'Avatar upload failed ($code).';
}
