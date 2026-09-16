import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../services/admin_service.dart';
import '../../services/pricing_service.dart';
import '../../widgets/ancho_maximo.dart';

/// Paleta de la pantalla de config (cards oscuras).
const _kCardBg = Color(0xFF1A1A1A);
const _kInputBg = Color(0xFF222222);
const _kInputBorder = Color(0xFF333333);
const _kSubtle = Color(0xFF8F8A85);

class AdminConfigScreen extends StatefulWidget {
  const AdminConfigScreen({super.key});

  @override
  State<AdminConfigScreen> createState() => _AdminConfigScreenState();
}

class _AdminConfigScreenState extends State<AdminConfigScreen> {
  final _service = AdminService();
  final _pricingService = PricingService();
  final _creditValueCtrl = TextEditingController();
  final _newCategoryCtrl = TextEditingController();

  bool _loading = true;
  bool _savingCredit = false;
  bool _savingCategory = false;
  String? _error;

  /// Bono de bienvenida. `null` = la migración todavía no está aplicada; la
  /// card lo dice y el resto de la pantalla sigue funcionando igual.
  Map<String, dynamic>? _bono;
  Map<String, dynamic>? _bonoMetricas;
  String? _bonoError;
  bool _savingBono = false;

  /// {nombre, activa, en_uso} por categoría. El backoffice ve también
  /// las desactivadas; los selectores del estudio no.
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _plans = [];

  // Preview de packs en vivo mientras edita el valor
  int _valorCreditoActual = 1000;
  int _valorCreditoPreview = 1000;

  @override
  void initState() {
    super.initState();
    _creditValueCtrl.addListener(_actualizarPreviewValor);
    _load();
  }

  @override
  void dispose() {
    _creditValueCtrl.removeListener(_actualizarPreviewValor);
    _creditValueCtrl.dispose();
    _newCategoryCtrl.dispose();
    super.dispose();
  }

  void _actualizarPreviewValor() {
    final parsed = int.tryParse(_creditValueCtrl.text.trim());
    if (parsed == null || parsed <= 0) return;
    if (parsed == _valorCreditoPreview) return;
    setState(() => _valorCreditoPreview = parsed);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final categories = await _service.listStudyCategoriesDetalle();
      final plans = await _service.listPricingPlans();
      final valorCreditoArs = await _service.getValorCreditoArs();
      if (!mounted) return;

      _creditValueCtrl.text = '$valorCreditoArs';

      setState(() {
        _categories = categories;
        _plans = plans;
        _valorCreditoActual = valorCreditoArs;
        _valorCreditoPreview = valorCreditoArs;
        _loading = false;
      });
      // Aparte y después: si el bono falla (migración sin aplicar), la
      // pantalla de precios tiene que seguir andando igual.
      await _cargarBono();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  // ── Bono de bienvenida ──────────────────────────────────────────────────
  Future<void> _cargarBono() async {
    try {
      final cfg = await _service.getBonoConfig();
      final met = await _service.getBonoMetricas();
      if (!mounted) return;
      setState(() {
        _bono = cfg;
        _bonoMetricas = Map<String, dynamic>.from(met['grupos'] as Map? ?? {});
        _bonoError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bono = null;
        _bonoError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _togglearBono(bool prender) async {
    final cfg = _bono;
    if (cfg == null) return;
    if (prender) {
      final ok = await _confirmar(
        titulo: '¿Prender el bono?',
        cuerpo:
            'Desde este momento, cada cuenta nueva recibe ${cfg['monto']} '
            'créditos al registrarse, hasta ${cfg['tope_nuevas']} cuentas.\n\n'
            'A las ya registradas NO les llega nada todavía: eso se hace con '
            'el botón de abajo, cuando quieras.',
        confirmar: 'Prender',
      );
      if (!ok) return;
    }
    setState(() => _savingBono = true);
    try {
      if (prender) {
        await _service.prenderBono(
          monto: (cfg['monto'] as num).toInt(),
          topeRegistradas: (cfg['tope_registradas'] as num).toInt(),
          topeNuevas: (cfg['tope_nuevas'] as num).toInt(),
        );
      } else {
        await _service.apagarBono();
      }
      await _cargarBono();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(prender ? 'Bono prendido.' : 'Bono apagado.'),
          backgroundColor: prender ? AppColors.success : null,
        ),
      );
    } catch (e) {
      _mostrarError(e);
    } finally {
      if (mounted) setState(() => _savingBono = false);
    }
  }

  Future<void> _otorgarRegistradas() async {
    final cfg = _bono;
    if (cfg == null) return;
    final cupo = (cfg['tope_registradas'] as num).toInt() -
        (cfg['dados_registradas'] as num).toInt();
    if (cupo <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ya se otorgó el tope de este grupo.')),
      );
      return;
    }
    final ok = await _confirmar(
      titulo: '¿Otorgar a $cupo usuarias?',
      cuerpo:
          'Se les acreditan ${cfg['monto']} créditos a las $cupo usuarias más '
          'activas que nunca compraron un pack, y se les avisa por la '
          'campanita, push y mail.\n\nEsto regala créditos de verdad y no se '
          'puede deshacer con un botón.',
      confirmar: 'Otorgar',
    );
    if (!ok) return;
    setState(() => _savingBono = true);
    try {
      final n = await _service.otorgarBonoRegistradas();
      await _cargarBono();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bono otorgado a $n usuarias.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      _mostrarError(e);
    } finally {
      if (mounted) setState(() => _savingBono = false);
    }
  }

  Future<bool> _confirmar({
    required String titulo,
    required String cuerpo,
    required String confirmar,
  }) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCardBg,
        title: Text(titulo, style: const TextStyle(color: Colors.white)),
        content: Text(cuerpo, style: const TextStyle(color: _kSubtle, height: 1.45)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text(confirmar),
          ),
        ],
      ),
    );
    return res == true;
  }

  void _mostrarError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: AppColors.error,
      ),
    );
  }

  Future<void> _guardarValorCredito() async {
    final value = int.tryParse(_creditValueCtrl.text.trim());
    if (value == null || value <= 0) return;

    setState(() => _savingCredit = true);
    try {
      await _service.setValorCreditoArs(value);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Valor del crédito actualizado. Los packs y planes se recalcularon automáticamente.',
          ),
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
      if (mounted) setState(() => _savingCredit = false);
    }
  }

  /// Dar de baja en vez de borrar. Es la acción preferida: no toca las
  /// clases ni los estudios que ya la tienen asignada.
  Future<void> _toggleCategory(String nombre, bool activa) async {
    try {
      await _service.toggleStudyCategory(nombre, activa);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            activa
                ? '"$nombre" activada.'
                : '"$nombre" desactivada. Deja de aparecer en los selectores.',
          ),
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
    }
  }

  Future<void> _agregarCategoria() async {
    final value = _newCategoryCtrl.text.trim();
    if (value.isEmpty) return;
    setState(() => _savingCategory = true);
    try {
      await _service.addStudyCategory(value);
      _newCategoryCtrl.clear();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Categoría agregada.'),
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
      if (mounted) setState(() => _savingCategory = false);
    }
  }

  Future<void> _renameCategory(String current) async {
    final ctrl = TextEditingController(text: current);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar categoría'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Nombre'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _service.renameStudyCategory(oldName: current, newName: ctrl.text);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _deleteCategory(String current) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar categoría'),
        content: Text(
          'Se va a eliminar "$current". Los estudios que la usen quedarán sin categoría.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _service.deleteStudyCategory(current);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _editPlan([Map<String, dynamic>? plan]) async {
    final nombreCtrl = TextEditingController(
      text: plan?['nombre']?.toString() ?? '',
    );
    final creditosCtrl = TextEditingController(
      text: '${(plan?['creditos'] as num?)?.toInt() ?? 0}',
    );
    final precioCtrl = TextEditingController(
      text: '${(plan?['precio'] as num?)?.toInt() ?? 0}',
    );
    final descripcionCtrl = TextEditingController(
      text: plan?['descripcion']?.toString() ?? '',
    );
    final ordenCtrl = TextEditingController(
      text: '${(plan?['orden'] as num?)?.toInt() ?? (_plans.length + 1)}',
    );
    bool activo = plan?['activo'] as bool? ?? true;
    bool destacado = plan?['destacado'] as bool? ?? false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(plan == null ? 'Nuevo plan' : 'Editar plan'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: creditosCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Créditos'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: precioCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Precio'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descripcionCtrl,
                  decoration: const InputDecoration(labelText: 'Descripción'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ordenCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Orden'),
                ),
                SwitchListTile(
                  value: destacado,
                  onChanged: (v) => setLocal(() => destacado = v),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Destacado'),
                ),
                SwitchListTile(
                  value: activo,
                  onChanged: (v) => setLocal(() => activo = v),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Activo'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    await _service.upsertPricingPlan(
      id: (plan?['id'] as num?)?.toInt(),
      nombre: nombreCtrl.text,
      creditos: int.tryParse(creditosCtrl.text) ?? 0,
      precio: int.tryParse(precioCtrl.text) ?? 0,
      descripcion: descripcionCtrl.text,
      ahorro: null,
      destacado: destacado,
      activo: activo,
      orden: int.tryParse(ordenCtrl.text) ?? 0,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        toolbarHeight: 0,
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: AnchoMaximo(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Config global',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () => context.go('/home'),
                        child: const Text('Volver a usuario'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Ajustes globales rápidos para operar Aura sin entrar a Supabase.',
                    style: TextStyle(color: AppColors.grey),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    _Block(
                      title: 'No se pudo cargar configuración',
                      body: _error!,
                    )
                  else ...[
                    // 1. VALOR DEL CRÉDITO
                    _ValorCreditoCard(
                      controller: _creditValueCtrl,
                      valorActual: _valorCreditoActual,
                      saving: _savingCredit,
                      onGuardar: _guardarValorCredito,
                    ),
                    const SizedBox(height: 14),
                    // 2. PACKS DE CRÉDITOS (auto-calculados)
                    _PacksCard(
                      valorCredito: _valorCreditoPreview,
                      pricingService: _pricingService,
                      cambiado: _valorCreditoPreview != _valorCreditoActual,
                    ),
                    const SizedBox(height: 14),
                    // 3. PLANES (suscripciones)
                    _PlanesCard(
                      plans: _plans,
                      onAdd: () => _editPlan(),
                      onEdit: _editPlan,
                    ),
                    const SizedBox(height: 14),
                    // 4. CATEGORÍAS DE ESTUDIOS
                    _CategoriasCard(
                      categories: _categories,
                      controller: _newCategoryCtrl,
                      saving: _savingCategory,
                      onAdd: _agregarCategoria,
                      onRename: _renameCategory,
                      onDelete: _deleteCategory,
                      onToggle: _toggleCategory,
                    ),
                    const SizedBox(height: 14),
                    // 5. BONO DE BIENVENIDA
                    _BonoCard(
                      config: _bono,
                      metricas: _bonoMetricas,
                      error: _bonoError,
                      saving: _savingBono,
                      onToggle: _togglearBono,
                      onOtorgar: _otorgarRegistradas,
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

// ───────────────────────── helpers de estilo oscuro ─────────────────────

ButtonStyle _darkOutlinedStyle() => OutlinedButton.styleFrom(
  foregroundColor: Colors.white,
  side: const BorderSide(color: _kInputBorder),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
);

String _fmtPesos(int n) => n.toString().replaceAllMapped(
  RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
  (m) => '${m[1]}.',
);

/// Bono de bienvenida: interruptor, el botón de otorgar a las ya registradas
/// y la medición de los dos grupos.
///
/// Prender y otorgar son DOS acciones distintas a propósito. Prender sólo
/// abre la puerta a las cuentas nuevas; regalarle créditos a las que ya
/// estaban es una decisión aparte, con su propia confirmación, porque es
/// plata y no se deshace con un botón.
class _BonoCard extends StatelessWidget {
  final Map<String, dynamic>? config;
  final Map<String, dynamic>? metricas;
  final String? error;
  final bool saving;
  final void Function(bool) onToggle;
  final VoidCallback onOtorgar;

  const _BonoCard({
    required this.config,
    required this.metricas,
    required this.error,
    required this.saving,
    required this.onToggle,
    required this.onOtorgar,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = config;
    if (cfg == null) {
      return _DarkCard(
        title: 'Bono de bienvenida',
        subtitle: error ?? 'No se pudo leer el estado del bono.',
        children: const [],
      );
    }

    final activo = cfg['activo'] == true;
    final monto = (cfg['monto'] as num?)?.toInt() ?? 0;
    final dadosReg = (cfg['dados_registradas'] as num?)?.toInt() ?? 0;
    final topeReg = (cfg['tope_registradas'] as num?)?.toInt() ?? 0;
    final dadosNue = (cfg['dados_nuevas'] as num?)?.toInt() ?? 0;
    final topeNue = (cfg['tope_nuevas'] as num?)?.toInt() ?? 0;
    final candidatas = (cfg['candidatas_registradas'] as num?)?.toInt() ?? 0;
    final dias = (cfg['vencimiento_dias'] as num?)?.toInt() ?? 60;

    return _DarkCard(
      title: 'Bono de bienvenida',
      subtitle: '$monto créditos por cuenta, una sola vez, que vencen a los '
          '$dias días. Dos grupos con topes separados.',
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                activo ? 'Prendido' : 'Apagado',
                style: TextStyle(
                  color: activo ? AppColors.success : _kSubtle,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (saving)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Switch(
                value: activo,
                activeThumbColor: AppColors.primary,
                onChanged: onToggle,
              ),
          ],
        ),
        const SizedBox(height: 14),
        _BonoGrupo(
          titulo: 'Ya registradas (nunca compraron un pack)',
          dados: dadosReg,
          tope: topeReg,
          metricas: metricas?['registradas'] as Map?,
          extra: '$candidatas candidatas disponibles',
        ),
        const SizedBox(height: 10),
        _BonoGrupo(
          titulo: 'Cuentas nuevas (se acredita sola al registrarse)',
          dados: dadosNue,
          tope: topeNue,
          metricas: metricas?['nuevas'] as Map?,
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton(
            onPressed: (!activo || saving || dadosReg >= topeReg) ? null : onOtorgar,
            style: _darkOutlinedStyle(),
            child: Text(
              dadosReg >= topeReg
                  ? 'Tope alcanzado en las ya registradas'
                  : 'Otorgar a las ya registradas (${topeReg - dadosReg})',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          activo
              ? 'Arranca por las que entraron a la app más recientemente. Les '
                  'avisa por campanita, push y mail.'
              : 'Prendé el bono para poder otorgarlo.',
          style: const TextStyle(color: _kSubtle, fontSize: 12, height: 1.4),
        ),
      ],
    );
  }
}

/// Una fila de medición por grupo: cuántas lo recibieron, cuántas lo usaron
/// en una clase y cuántas compraron un pack después.
class _BonoGrupo extends StatelessWidget {
  final String titulo;
  final int dados;
  final int tope;
  final Map? metricas;
  final String? extra;

  const _BonoGrupo({
    required this.titulo,
    required this.dados,
    required this.tope,
    required this.metricas,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    final m = metricas;
    final usaron = (m?['usaron_en_clase'] as num?)?.toInt() ?? 0;
    final compraron = (m?['compraron_pack'] as num?)?.toInt() ?? 0;
    final usados = (m?['creditos_usados'] as num?)?.toInt() ?? 0;
    final otorgados = (m?['creditos_otorgados'] as num?)?.toInt() ?? 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kInputBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titulo,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Recibieron $dados de $tope'
            '${extra != null ? ' · $extra' : ''}',
            style: const TextStyle(color: _kSubtle, fontSize: 12, height: 1.5),
          ),
          Text(
            'Lo usaron en una clase: $usaron · Compraron un pack después: $compraron',
            style: const TextStyle(color: _kSubtle, fontSize: 12, height: 1.5),
          ),
          Text(
            'Créditos quemados: $usados de $otorgados',
            style: const TextStyle(color: _kSubtle, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// Card oscura reutilizable con título.
class _DarkCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;

  const _DarkCard({
    required this.title,
    this.subtitle,
    this.trailing,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: const TextStyle(
                color: _kSubtle,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

// ─────────────────────────── 1. Valor del crédito ───────────────────────

class _ValorCreditoCard extends StatelessWidget {
  final TextEditingController controller;
  final int valorActual;
  final bool saving;
  final VoidCallback onGuardar;

  const _ValorCreditoCard({
    required this.controller,
    required this.valorActual,
    required this.saving,
    required this.onGuardar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Valor del crédito',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Actual: \$${_fmtPesos(valorActual)} ARS por crédito',
            style: const TextStyle(color: _kSubtle, fontSize: 12),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            decoration: const InputDecoration(
              labelText: 'Nuevo valor',
              labelStyle: TextStyle(color: _kSubtle),
              prefixText: '\$ ',
              prefixStyle: TextStyle(color: Colors.white),
              filled: true,
              fillColor: _kInputBg,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
                borderSide: BorderSide(color: _kInputBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
                borderSide: BorderSide(color: AppColors.primary, width: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: saving ? null : onGuardar,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Actualizar',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Al cambiar este valor todos los packs y planes se actualizan solos.',
            style: TextStyle(color: _kSubtle, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── 2. Packs de créditos ───────────────────────

class _PacksCard extends StatelessWidget {
  final int valorCredito;
  final PricingService pricingService;
  final bool cambiado;

  const _PacksCard({
    required this.valorCredito,
    required this.pricingService,
    required this.cambiado,
  });

  @override
  Widget build(BuildContext context) {
    final packs = pricingService.packsConValor(valorCredito);
    return _DarkCard(
      title: 'Packs de créditos',
      subtitle:
          'Se calculan automáticamente desde el valor del crédito. No se editan a mano.',
      trailing: cambiado
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'NUEVO',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : null,
      children: packs.map((pack) {
        final nombre = pack['nombre']?.toString() ?? '';
        final creditos = (pack['creditos'] as num).toInt();
        final precio = (pack['precio'] as num).toInt();
        final vigencia = (pack['vigencia_dias'] as num?)?.toInt() ?? 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$creditos cr · $vigencia días',
                      style: const TextStyle(color: _kSubtle, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Text(
                '\$${_fmtPesos(precio)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────── 3. Planes ──────────────────────────────

class _PlanesCard extends StatelessWidget {
  final List<Map<String, dynamic>> plans;
  final VoidCallback onAdd;
  final void Function(Map<String, dynamic>) onEdit;

  const _PlanesCard({
    required this.plans,
    required this.onAdd,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return _DarkCard(
      title: 'Planes (suscripciones)',
      subtitle:
          'Disponibles pero no promocionados activamente. Editá su configuración acá.',
      trailing: OutlinedButton.icon(
        onPressed: onAdd,
        style: _darkOutlinedStyle(),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Agregar'),
      ),
      children: [
        if (plans.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No hay planes configurados.',
              style: TextStyle(color: _kSubtle, fontSize: 13),
            ),
          ),
        ...plans.map(
          (item) => Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _kInputBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['nombre']?.toString() ?? 'Sin nombre',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${(item['creditos'] as num?)?.toInt() ?? 0} cr · \$${_fmtPesos((item['precio'] as num?)?.toInt() ?? 0)}',
                        style: const TextStyle(color: _kSubtle, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  onPressed: () => onEdit(item),
                  style: _darkOutlinedStyle(),
                  child: const Text('Editar'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── 4. Categorías de estudios ────────────────────

class _CategoriasCard extends StatelessWidget {
  final List<Map<String, dynamic>> categories;
  final TextEditingController controller;
  final bool saving;
  final VoidCallback onAdd;
  final void Function(String) onRename;
  final void Function(String) onDelete;
  final void Function(String nombre, bool activa) onToggle;

  const _CategoriasCard({
    required this.categories,
    required this.controller,
    required this.saving,
    required this.onAdd,
    required this.onRename,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return _DarkCard(
      title: 'Categorías de estudios',
      subtitle:
          'Única fuente de verdad. Los estudios solo asignan de esta lista; '
          'no pueden crear categorías. Desactivar una la saca de los '
          'selectores sin tocar las clases que ya la usan.',
      children: [
        if (categories.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No hay categorías todavía.',
              style: TextStyle(color: _kSubtle, fontSize: 13),
            ),
          ),
        ...categories.map((row) {
          final nombre = row['nombre']?.toString() ?? '';
          final activa = row['activa'] != false;
          final enUso = (row['en_uso'] as num?)?.toInt() ?? 0;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(
              color: _kInputBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre,
                        style: TextStyle(
                          // Las desactivadas se ven apagadas: siguen ahí
                          // pero ya no se pueden asignar.
                          color: activa ? Colors.white : _kSubtle,
                          fontWeight: FontWeight.w600,
                          decoration: activa
                              ? TextDecoration.none
                              : TextDecoration.lineThrough,
                        ),
                      ),
                      Text(
                        enUso == 0
                            ? 'Sin estudios asignados'
                            : 'En uso por $enUso '
                                  'estudio${enUso == 1 ? '' : 's'}',
                        style: const TextStyle(color: _kSubtle, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: activa,
                  onChanged: (v) => onToggle(nombre, v),
                  activeThumbColor: AppColors.primary,
                ),
                const SizedBox(width: 4),
                OutlinedButton(
                  onPressed: () => onRename(nombre),
                  style: _darkOutlinedStyle(),
                  child: const Text('Editar'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => onDelete(nombre),
                  style: _darkOutlinedStyle().copyWith(
                    foregroundColor: const WidgetStatePropertyAll(
                      Color(0xFFE8763A),
                    ),
                  ),
                  child: const Text('Eliminar'),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Nueva categoría',
                  labelStyle: TextStyle(color: _kSubtle),
                  filled: true,
                  fillColor: _kInputBg,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(color: _kInputBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                    borderSide: BorderSide(
                      color: AppColors.primary,
                      width: 1.4,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: saving ? null : onAdd,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Agregar'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────── utilitarios ────────────────────────────

class _Block extends StatelessWidget {
  final String title;
  final String body;

  const _Block({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(color: AppColors.grey, height: 1.5),
          ),
        ],
      ),
    );
  }
}
