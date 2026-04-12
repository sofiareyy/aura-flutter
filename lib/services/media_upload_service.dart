import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MediaUploadService {
  final _picker = ImagePicker();
  final _client = Supabase.instance.client;

  Future<String?> pickAndUpload({
    required String bucket,
    required String folder,
    required String userId,
  }) async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1600,
    );
    if (file == null) return null;

    final bytes = await file.readAsBytes();
    final ext = _ext(file.name);
    final path =
        '$folder/$userId/${DateTime.now().millisecondsSinceEpoch}.$ext';

    try {
      await _uploadBytes(bucket: bucket, path: path, bytes: bytes);
      return _client.storage.from(bucket).getPublicUrl(path);
    } catch (e) {
      throw Exception(
        'No se pudo subir la imagen. Revisá Storage y volvé a intentarlo.',
      );
    }
  }

  Future<void> _uploadBytes({
    required String bucket,
    required String path,
    required Uint8List bytes,
  }) async {
    await _client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            cacheControl: '3600',
            upsert: true,
          ),
        );
  }

  String _ext(String name) {
    final dot = name.lastIndexOf('.');
    if (dot == -1) return 'jpg';
    final ext = name.substring(dot + 1).toLowerCase();
    return ext.isEmpty ? 'jpg' : ext;
  }
}
