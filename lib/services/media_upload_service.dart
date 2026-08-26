import 'dart:typed_data';

import 'package:flutter/foundation.dart';

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
      debugPrint('[MediaUploadService.upload] $e');
      throw Exception(
        'No se pudo subir la imagen. Revisá Storage y volvé a intentarlo.',
      );
    }
  }

  /// Sube la foto de perfil al bucket `avatares` con path `{userId}/perfil.{ext}`.
  /// upsert reemplaza la foto anterior; siempre devuelve la URL pública con
  /// cache-buster por timestamp para forzar refresh del avatar en la UI.
  ///
  /// `source` existe porque Mi Perfil deja elegir cámara o galería. Antes esa
  /// pantalla tenía su propia copia del upload (forzaba `.jpg` y
  /// `image/jpeg`, esta respeta la extensión) y ya habían divergido: dos
  /// caminos para lo mismo. Ahora las dos pantallas pasan por acá.
  Future<String?> uploadAvatar({
    required String userId,
    ImageSource source = ImageSource.gallery,
  }) async {
    final file = await _picker.pickImage(
      source: source,
      imageQuality: 82,
      maxWidth: 1600,
    );
    if (file == null) return null;

    final bytes = await file.readAsBytes();
    final ext = _ext(file.name);
    final path = '$userId/perfil.$ext';

    try {
      await _uploadBytes(bucket: 'avatares', path: path, bytes: bytes);
      final base = _client.storage.from('avatares').getPublicUrl(path);
      return '$base?t=${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      // El catch genérico es lo que escondió el bug de las policies faltantes
      // durante meses: mostraba "revisá Storage" y descartaba el
      // `violates row-level security policy` que lo resolvía en minutos.
      // El texto para la usuaria queda igual; la causa va al log.
      debugPrint('[uploadAvatar] $e');
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
