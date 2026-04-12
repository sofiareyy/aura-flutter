import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/app_provider.dart';
import '../../services/media_upload_service.dart';
import '../../services/usuarios_service.dart';

class EditarPerfilScreen extends StatefulWidget {
  const EditarPerfilScreen({super.key});

  @override
  State<EditarPerfilScreen> createState() => _EditarPerfilScreenState();
}

class _EditarPerfilScreenState extends State<EditarPerfilScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usuariosService = UsuariosService();
  final _mediaUploadService = MediaUploadService();
  final _nombreCtrl = TextEditingController();
  final _avatarCtrl = TextEditingController();

  bool _saving = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    final usuario = context.read<AppProvider>().usuario;
    _nombreCtrl.text = usuario?.nombre ?? '';
    _avatarCtrl.text = usuario?.avatarUrl ?? '';
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _avatarCtrl.dispose();
    super.dispose();
  }

  Future<void> _subirFoto() async {
    final provider = context.read<AppProvider>();
    if (provider.userId.isEmpty) return;

    setState(() => _uploading = true);
    try {
      final url = await _mediaUploadService.pickAndUpload(
        bucket: 'user-media',
        folder: 'avatars',
        userId: provider.userId,
      );
      if (url == null || !mounted) return;
      setState(() => _avatarCtrl.text = url);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Foto subida correctamente.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    final provider = context.read<AppProvider>();
    if (provider.userId.isEmpty) return;

    setState(() => _saving = true);
    try {
      await _usuariosService.updateUsuario(
        provider.userId,
        {
          'nombre': _nombreCtrl.text.trim(),
          'avatar_url':
              _avatarCtrl.text.trim().isEmpty ? null : _avatarCtrl.text.trim(),
        },
      );
      await provider.refrescarUsuario();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Perfil actualizado.'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = _avatarCtrl.text.trim();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Editar perfil')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 42,
                    backgroundColor: AppColors.primaryLight,
                    backgroundImage:
                        avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                    child: avatarUrl.isEmpty
                        ? Text(
                            _nombreCtrl.text.trim().isEmpty
                                ? 'A'
                                : _nombreCtrl.text.trim()[0].toUpperCase(),
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Podés subir una foto o usar una URL.',
                    style: TextStyle(color: AppColors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: _uploading ? null : _subirFoto,
                    child: _uploading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Subir foto'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nombreCtrl,
              decoration: const InputDecoration(labelText: 'Nombre'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Ingresá tu nombre.';
                }
                return null;
              },
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _avatarCtrl,
              decoration: const InputDecoration(
                labelText: 'URL de foto',
                hintText: 'https://...',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 24),
            const Text(
              'La imagen queda guardada en Storage para que el perfil no dependa solo de URLs externas.',
              style: TextStyle(
                color: AppColors.grey,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _guardar,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: AppColors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Guardar cambios'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
