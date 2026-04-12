import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../services/reviews_service.dart';

class StudyReviewSheet extends StatefulWidget {
  final int estudioId;
  final int? claseId;
  final String estudioNombre;
  final String? experienciaLabel;

  const StudyReviewSheet({
    super.key,
    required this.estudioId,
    required this.estudioNombre,
    this.claseId,
    this.experienciaLabel,
  });

  static Future<bool?> show(
    BuildContext context, {
    required int estudioId,
    required String estudioNombre,
    int? claseId,
    String? experienciaLabel,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StudyReviewSheet(
        estudioId: estudioId,
        estudioNombre: estudioNombre,
        claseId: claseId,
        experienciaLabel: experienciaLabel,
      ),
    );
  }

  @override
  State<StudyReviewSheet> createState() => _StudyReviewSheetState();
}

class _StudyReviewSheetState extends State<StudyReviewSheet> {
  final _service = ReviewsService();
  final _comentarioCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  int _rating = 5;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _comentarioCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final review = await _service.getMyReviewForStudy(widget.estudioId);
    if (!mounted) return;
    setState(() {
      _rating = (review?['rating'] as num?)?.toInt() ?? 5;
      _comentarioCtrl.text = review?['comentario']?.toString() ?? '';
      _loading = false;
    });
  }

  Future<void> _guardar() async {
    final comentario = _comentarioCtrl.text.trim();
    if (comentario.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contá un poco más sobre tu experiencia.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _service.upsertStudyReview(
        estudioId: widget.estudioId,
        claseId: widget.claseId,
        experienciaLabel: widget.experienciaLabel,
        rating: _rating,
        comentario: comentario,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
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
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF7F5F2),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottom + 20),
      child: _loading
          ? const SizedBox(
              height: 240,
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1CAC3),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Tu reseña para ${widget.estudioNombre}',
                  style: const TextStyle(
                    color: AppColors.black,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if ((widget.experienciaLabel ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1E8),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Experiencia: ${widget.experienciaLabel}',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                const Text(
                  '¿Cómo fue tu experiencia?',
                  style: TextStyle(
                    color: AppColors.black,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: List.generate(5, (index) {
                    final value = index + 1;
                    return IconButton(
                      onPressed: () => setState(() => _rating = value),
                      icon: Icon(
                        value <= _rating ? Icons.star_rounded : Icons.star_border_rounded,
                        color: value <= _rating ? AppColors.primary : const Color(0xFFBEB6AF),
                        size: 30,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _comentarioCtrl,
                  minLines: 4,
                  maxLines: 6,
                  decoration: InputDecoration(
                    hintText: 'Contanos cómo fue la clase, el lugar, la atención o lo que más te gustó.',
                    filled: true,
                    fillColor: AppColors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _guardar,
                    child: Text(_saving ? 'Guardando...' : 'Guardar reseña'),
                  ),
                ),
              ],
            ),
    );
  }
}
