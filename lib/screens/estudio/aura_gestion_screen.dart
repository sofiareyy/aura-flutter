import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/aura_gestion_design.dart';
import '../../services/aura_gestion_service.dart';
import '../../services/estudio_admin_service.dart';

class AuraGestionScreen extends StatefulWidget {
  const AuraGestionScreen({super.key});

  @override
  State<AuraGestionScreen> createState() => _AuraGestionScreenState();
}

class _AuraGestionScreenState extends State<AuraGestionScreen> {
  final _gestionService = AuraGestionService();
  final _estudioAdminService = EstudioAdminService();
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _alumnos = const [];
  List<Map<String, dynamic>> _filtrados = const [];
  bool _loading = true;
  int? _estudioId;
  String _modo = 'gestion';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_aplicarFiltro);
    _cargar();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final estudioId = await _estudioAdminService.getCurrentStudioId();
      if (estudioId == null) {
        if (!mounted) return;
        setState(() {
          _estudioId = null;
          _alumnos = const [];
          _filtrados = const [];
          _loading = false;
        });
        return;
      }

      final results = await Future.wait([
        _gestionService.listarAlumnos(estudioId),
        _gestionService.getModoEstudio(estudioId),
      ]);

      final alumnos = List<Map<String, dynamic>>.from(results[0] as List);
      final modo = results[1] as String;

      if (!mounted) return;
      setState(() {
        _estudioId = estudioId;
        _alumnos = alumnos;
        _modo = modo;
        _loading = false;
      });
      _aplicarFiltro();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _alumnos = const [];
        _filtrados = const [];
      });
      AuraGestionDesign.showErrorSnackBar(
        context,
        'No pudimos cargar tus alumnos.',
      );
    }
  }

  void _aplicarFiltro() {
    final query = _searchController.text.trim().toLowerCase();
    final filtrados = query.isEmpty
        ? _alumnos
        : _alumnos.where((alumno) {
            final nombre = (alumno['nombre'] ?? '').toString().toLowerCase();
            final email = (alumno['email'] ?? '').toString().toLowerCase();
            return nombre.contains(query) || email.contains(query);
          }).toList();

    if (!mounted) return;
    setState(() => _filtrados = filtrados);
  }

  Future<void> _mostrarAgregarAlumnoSheet() async {
    final nombreController = TextEditingController();
    final emailController = TextEditingController();
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AuraGestionDesign.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> submit() async {
              if (_estudioId == null) return;
              if (nombreController.text.trim().isEmpty ||
                  emailController.text.trim().isEmpty) {
                AuraGestionDesign.showErrorSnackBar(
                  context,
                  'Completá nombre y email.',
                );
                return;
              }
              setModalState(() => saving = true);
              try {
                await _gestionService.agregarAlumno(
                  estudioId: _estudioId!,
                  nombre: nombreController.text,
                  email: emailController.text,
                );
                if (!mounted) return;
                Navigator.of(context).pop();
                await _cargar();
                if (!mounted) return;
                AuraGestionDesign.showSuccessSnackBar(
                  this.context,
                  'Alumno agregado.',
                );
              } catch (e) {
                setModalState(() => saving = false);
                AuraGestionDesign.showErrorSnackBar(
                  context,
                  'No pudimos agregar este alumno.',
                );
              }
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                20 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AuraGestionDesign.border,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Agregar alumno',
                    style: AuraGestionDesign.titleStyle(size: 18),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: nombreController,
                    textCapitalization: TextCapitalization.words,
                    style: AuraGestionDesign.bodyStyle(),
                    decoration: AuraGestionDesign.inputDecoration(
                      label: 'Nombre',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: AuraGestionDesign.bodyStyle(),
                    decoration: AuraGestionDesign.inputDecoration(
                      label: 'Email',
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: saving ? null : submit,
                    style: AuraGestionDesign.primaryButtonStyle(),
                    child: Text(saving ? 'Agregando...' : 'Agregar'),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: saving ? null : () => Navigator.of(context).pop(),
                      child: Text(
                        'Cancelar',
                        style: AuraGestionDesign.bodyStyle(
                          color: AuraGestionDesign.textSecondary,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _mostrarCambiarModoSheet() async {
    if (_estudioId == null) return;
    String selected = _modo;
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AuraGestionDesign.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> confirm() async {
              setModalState(() => saving = true);
              try {
                await _gestionService.cambiarModoEstudio(
                  estudioId: _estudioId!,
                  modo: selected,
                );
                if (!mounted) return;
                Navigator.of(context).pop();
                await _cargar();
                if (!mounted) return;
                AuraGestionDesign.showSuccessSnackBar(
                  this.context,
                  'Modo actualizado.',
                );
              } catch (_) {
                setModalState(() => saving = false);
                AuraGestionDesign.showErrorSnackBar(
                  context,
                  'No pudimos cambiar el modo.',
                );
              }
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                20 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AuraGestionDesign.border,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Cambiar modo',
                    style: AuraGestionDesign.titleStyle(size: 18),
                  ),
                  const SizedBox(height: 18),
                  _ModoOptionCard(
                    selected: selected == 'gestion',
                    icon: Icons.workspace_premium_outlined,
                    title: 'Gestión Gratuita',
                    subtitle:
                        'Tus alumnos reservan sin créditos. Sin comisión.',
                    onTap: () => setModalState(() => selected = 'gestion'),
                  ),
                  const SizedBox(height: 12),
                  _ModoOptionCard(
                    selected: selected == 'marketplace',
                    icon: Icons.storefront_outlined,
                    title: 'Marketplace Aura',
                    subtitle:
                        'Aparecés para todos los usuarios de Aura. Comisión 30% sobre nuevos alumnos.',
                    onTap: () => setModalState(() => selected = 'marketplace'),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: saving ? null : confirm,
                    style: AuraGestionDesign.primaryButtonStyle(),
                    child: Text(saving ? 'Guardando...' : 'Confirmar'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _mostrarAlumnoActionsSheet(Map<String, dynamic> alumno) async {
    if (_estudioId == null) return;
    final alumnoId = (alumno['id'] as num?)?.toInt();
    if (alumnoId == null) return;
    final activo = alumno['activo'] == true;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AuraGestionDesign.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AuraGestionDesign.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                alumno['nombre']?.toString() ?? 'Alumno',
                style: AuraGestionDesign.titleStyle(size: 18),
              ),
              const SizedBox(height: 16),
              _SheetActionTile(
                icon: activo ? Icons.pause_circle_outline : Icons.check_circle_outline,
                label: activo ? 'Marcar como inactivo' : 'Marcar como activo',
                onTap: () async {
                  Navigator.of(context).pop();
                  await _gestionService.toggleAlumnoActivo(
                    estudioId: _estudioId!,
                    alumnoId: alumnoId,
                    activo: !activo,
                  );
                  await _cargar();
                },
              ),
              const SizedBox(height: 8),
              _SheetActionTile(
                icon: Icons.delete_outline,
                label: 'Eliminar alumno',
                destructive: true,
                onTap: () async {
                  Navigator.of(context).pop();
                  await _gestionService.eliminarAlumno(
                    estudioId: _estudioId!,
                    alumnoId: alumnoId,
                  );
                  await _cargar();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AuraGestionDesign.background,
      appBar: AppBar(
        backgroundColor: AuraGestionDesign.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
          color: AuraGestionDesign.textPrimary,
        ),
        title: Text(
          'Mis Alumnos',
          style: AuraGestionDesign.titleStyle(),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AuraGestionDesign.accent,
        onPressed: _mostrarAgregarAlumnoSheet,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: RefreshIndicator(
        color: AuraGestionDesign.accent,
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AuraGestionDesign.horizontalPadding,
            8,
            AuraGestionDesign.horizontalPadding,
            96,
          ),
          children: [
            _buildModoCard(),
            const SizedBox(height: AuraGestionDesign.sectionSpacing),
            Text(
              'MIS ALUMNOS',
              style: AuraGestionDesign.sectionLabelStyle(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              style: AuraGestionDesign.bodyStyle(),
              decoration: AuraGestionDesign.inputDecoration(
                label: 'Buscar alumno',
                hint: 'Nombre o email',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AuraGestionDesign.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_loading) ..._buildLoadingState() else ..._buildListState(),
          ],
        ),
      ),
    );
  }

  Widget _buildModoCard() {
    final isGestion = _modo == 'gestion';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AuraGestionDesign.premiumCard,
        borderRadius: BorderRadius.circular(AuraGestionDesign.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Modo actual',
            style: AuraGestionDesign.titleStyle(
              size: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AuraGestionDesign.softBadge,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isGestion ? 'Gestión Gratuita' : 'Marketplace Aura',
              style: AuraGestionDesign.bodyStyle(
                color: AuraGestionDesign.accent,
                size: 13,
                weight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isGestion
                ? 'Tus alumnos reservan gratis con su email y sin consumir créditos.'
                : 'Aparecés en Aura para nuevos alumnos y cobrás con comisión sobre ingresos nuevos.',
            style: AuraGestionDesign.bodyStyle(
              color: AuraGestionDesign.creamText.withOpacity(0.82),
              size: 14,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _mostrarCambiarModoSheet,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white24),
              minimumSize: const Size(150, 44),
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(AuraGestionDesign.buttonRadius),
              ),
              textStyle: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('Cambiar modo'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildLoadingState() {
    return List.generate(
      5,
      (index) => Padding(
        padding: EdgeInsets.only(bottom: index == 4 ? 0 : 12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AuraGestionDesign.card,
            borderRadius: BorderRadius.circular(AuraGestionDesign.cardRadius),
            boxShadow: const [AuraGestionDesign.softShadow],
          ),
          child: Row(
            children: [
              const AuraShimmerBox(
                height: 40,
                width: 40,
                borderRadius: BorderRadius.all(Radius.circular(999)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    AuraShimmerBox(
                      height: 14,
                      width: 140,
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                    SizedBox(height: 8),
                    AuraShimmerBox(
                      height: 12,
                      width: 180,
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildListState() {
    if (_filtrados.isEmpty) {
      return [
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
          decoration: BoxDecoration(
            color: AuraGestionDesign.card,
            borderRadius: BorderRadius.circular(AuraGestionDesign.cardRadius),
            boxShadow: const [AuraGestionDesign.softShadow],
          ),
          child: Column(
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: AuraGestionDesign.softBadge,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Icon(
                  Icons.groups_rounded,
                  color: AuraGestionDesign.accent,
                  size: 34,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Todavía no agregaste alumnos',
                style: AuraGestionDesign.bodyStyle(
                  weight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Agregá sus emails para que puedan reservar tus clases sin créditos',
                style: AuraGestionDesign.bodyStyle(
                  color: AuraGestionDesign.textSecondary,
                  size: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ];
    }

    return _filtrados
        .map(
          (alumno) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _AlumnoItem(
              alumno: alumno,
              onOptionsTap: () => _mostrarAlumnoActionsSheet(alumno),
            ),
          ),
        )
        .toList();
  }
}

class _AlumnoItem extends StatelessWidget {
  final Map<String, dynamic> alumno;
  final VoidCallback onOptionsTap;

  const _AlumnoItem({
    required this.alumno,
    required this.onOptionsTap,
  });

  @override
  Widget build(BuildContext context) {
    final nombre = alumno['nombre']?.toString().trim().isNotEmpty == true
        ? alumno['nombre'].toString().trim()
        : 'Alumno';
    final email = alumno['email']?.toString() ?? '';
    final activo = alumno['activo'] == true;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AuraGestionDesign.card,
        borderRadius: BorderRadius.circular(AuraGestionDesign.cardRadius),
        boxShadow: const [AuraGestionDesign.softShadow],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AuraGestionDesign.softBadge,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Center(
              child: Text(
                nombre.substring(0, 1).toUpperCase(),
                style: AuraGestionDesign.bodyStyle(
                  color: AuraGestionDesign.accent,
                  weight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombre,
                  style: AuraGestionDesign.bodyStyle(
                    weight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  style: AuraGestionDesign.bodyStyle(
                    color: AuraGestionDesign.textSecondary,
                    size: 13,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: activo
                  ? const Color(0xFFE9F7EF)
                  : const Color(0xFFF1F0EE),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              activo ? 'Activo' : 'Inactivo',
              style: AuraGestionDesign.bodyStyle(
                color: activo
                    ? const Color(0xFF2E7D32)
                    : AuraGestionDesign.textSecondary,
                size: 12,
                weight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: onOptionsTap,
            icon: const Icon(
              Icons.more_vert_rounded,
              color: AuraGestionDesign.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModoOptionCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ModoOptionCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AuraGestionDesign.cardRadius),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AuraGestionDesign.card,
          borderRadius: BorderRadius.circular(AuraGestionDesign.cardRadius),
          border: Border.all(
            color: selected
                ? AuraGestionDesign.accent
                : AuraGestionDesign.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AuraGestionDesign.softBadge,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AuraGestionDesign.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AuraGestionDesign.bodyStyle(
                      weight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: AuraGestionDesign.bodyStyle(
                      color: AuraGestionDesign.textSecondary,
                      size: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool destructive;
  final VoidCallback onTap;

  const _SheetActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? AuraGestionDesign.errorBg
        : AuraGestionDesign.textPrimary;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: destructive
              ? const Color(0xFFFFF1F1)
              : AuraGestionDesign.background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Text(
              label,
              style: AuraGestionDesign.bodyStyle(
                color: color,
                weight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
