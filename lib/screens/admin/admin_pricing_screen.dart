import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../services/admin_service.dart';
import '../../services/pricing_service.dart';
import '../../utils/pricing.dart';
import '../../utils/datos_cobro.dart';
import '../../utils/servicios_preview.dart';
import '../../widgets/ancho_maximo.dart';

class AdminPricingScreen extends StatefulWidget {
  final int estudioId;
  final String? estudioNombre;
  final bool readOnly;

  const AdminPricingScreen({
    super.key,
    required this.estudioId,
    this.estudioNombre,
    this.readOnly = false,
  });

  @override
  State<AdminPricingScreen> createState() => _AdminPricingScreenState();
}

class _AdminPricingScreenState extends State<AdminPricingScreen> {
  static const _picoColor = Color(0xFFE8763A);
  static const _valleColor = Color(0xFF4CAF50);

  static const _diasSemana = [
    '',
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];

  final _client = Supabase.instance.client;
  final _pricingService = PricingService();
  final _adminService = AdminService();

  // Servicios de precio fijo del estudio (backoffice, 3/9/2026). Se cargan y
  // se guardan APARTE del botón grande: cada cambio pasa por
  // admin_set_servicio_precio, que sólo toca clases futuras sin reserva, y
  // nunca por el recálculo general (que incluye pasadas).
  List<ServicioPrecio> _servicios = const [];
  List<String> _catalogo = const [];
  bool _guardandoServicio = false;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  String _tipoEstudio = 'fitness'; // 'fitness' | 'experiencia'
  // Modo de precio del estudio: 'fijo' (un único valor) o 'rango' (pico/valle
  // por horario). Es lo que decide qué hace la base en calcular_precio_clase.
  String _modo = 'fijo';
  int _valorCredito = 1000;
  double _comisionAura = 30;

  // fijo   -> _minCtrl es el valor único.
  // rango  -> _minCtrl es el valle y _maxCtrl el pico.
  final _minCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();
  // experiencia: precio fijo (legacy, ya no se muestra)
  final _fijoCtrl = TextEditingController();
  // experiencia: comisión de workshops (%). El precio lo pone el estudio en
  // cada workshop, no acá.
  final _comisionWorkshopCtrl = TextEditingController();

  // Franjas marcadas como valle: clave "dia|hora" (hora en punto, 0..23).
  // Solo se guardan las de valle; lo que no está acá es pico.
  final Map<String, String> _clasificacion = {};

  @override
  void initState() {
    super.initState();
    _minCtrl.addListener(_onPreviewChanged);
    _maxCtrl.addListener(_onPreviewChanged);
    _cargar();
  }

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    _fijoCtrl.dispose();
    _comisionWorkshopCtrl.dispose();
    super.dispose();
  }

  void _onPreviewChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _cargar() async {
    try {
      // Las comisiones salen de estudios_datos_cobro (ver DatosCobro); el resto
      // del pricing (precio_config/horarios_config/creditos_*) sigue en estudios.
      final rowRaw = await _client
          .from('estudios')
          .select(
            'id, nombre, tipo_estudio, tipo_precio, creditos_min, creditos_max, '
            'precio_config, horarios_config, '
            'estudios_datos_cobro(comision_workshop, comision_aura)',
          )
          .eq('id', widget.estudioId)
          .maybeSingle();
      final row = rowRaw == null
          ? null
          : DatosCobro.aplanar(Map<String, dynamic>.from(rowRaw));
      _valorCredito = await _pricingService.getValorCreditoArs();
      await _cargarServicios();

      if (row == null) {
        setState(() {
          _loading = false;
          _error = 'No se encontró el estudio.';
        });
        return;
      }

      _tipoEstudio = (row['tipo_estudio']?.toString() ?? 'fitness')
          .toLowerCase();
      _comisionAura = (row['comision_aura'] as num?)?.toDouble() ?? 30;

      _modo = (row['tipo_precio']?.toString() ?? 'fijo');
      if (_modo != 'fijo' && _modo != 'rango') _modo = 'fijo';

      // Fuente de verdad: creditos_min / creditos_max. precio_config quedó
      // deprecado y solo se lee como fallback para estudios sin migrar.
      final config = row['precio_config'];
      int? min = _asInt(row['creditos_min']);
      int? max = _asInt(row['creditos_max']);
      if (config is Map) {
        min ??= _asInt(config['min']);
        max ??= _asInt(config['max']);
      }
      _minCtrl.text = min?.toString() ?? '';
      _maxCtrl.text = max?.toString() ?? '';
      // para experiencia el precio fijo se guarda en min
      _fijoCtrl.text = min?.toString() ?? '';
      _comisionWorkshopCtrl.text = (_asInt(row['comision_workshop']) ?? 15)
          .toString();

      // horarios_config = {"valle": [{"dia":1,"hora":8}, ...]}
      // Solo valle: lo que no está marcado es pico.
      _clasificacion.clear();
      final horarios = row['horarios_config'];
      if (horarios is Map) {
        _cargarClasificacion(horarios['valle']);
      }

      setState(() {
        _loading = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Error: ${e.toString()}';
      });
    }
  }

  void _cargarClasificacion(dynamic arr) {
    if (arr is! List) return;
    for (final e in arr) {
      if (e is! Map) continue;
      final dia = _asInt(e['dia']);
      final hora = _asInt(e['hora']);
      if (dia != null && hora != null && dia >= 1 && dia <= 7) {
        _clasificacion['$dia|$hora'] = 'valle';
      }
    }
  }

  Future<void> _guardar() async {
    if (widget.readOnly) return;

    // Experiencia: no hay precio central (lo pone el estudio en cada workshop).
    // Solo se guarda tipo_estudio + comisión de workshops.
    if (_tipoEstudio == 'experiencia') {
      final comision = int.tryParse(_comisionWorkshopCtrl.text.trim()) ?? 15;
      setState(() => _saving = true);
      try {
        await _client
            .from('estudios')
            .update({'tipo_estudio': 'experiencia'})
            .eq('id', widget.estudioId);
        // comision_workshop vive ahora en estudios_datos_cobro y el trigger de
        // bloqueo no deja que un cliente la escriba directo: va por RPC
        // security definer, igual que admin_set_pricing_estudio.
        await _client.rpc(
          'admin_set_comision_workshop',
          params: {'p_estudio_id': widget.estudioId, 'p_comision': comision},
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configuración guardada.'),
            backgroundColor: AppColors.success,
          ),
        );
      } catch (e) {
        _snack('No se pudo guardar: $e');
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }

    final min = int.tryParse(_minCtrl.text.trim());
    if (min == null || min <= 0) {
      _snack(
        _modo == 'fijo'
            ? 'Completá los créditos por clase.'
            : 'Completá el precio mínimo.',
      );
      return;
    }

    int? max;
    Map<String, dynamic>? horariosConfig;
    if (_modo == 'rango') {
      max = int.tryParse(_maxCtrl.text.trim());
      if (max == null) {
        _snack('Completá el precio máximo.');
        return;
      }
      if (max < min) {
        _snack('El precio máximo no puede ser menor al mínimo.');
        return;
      }
      // Solo se persiste `valle`. Guardar también `pico` sería estado
      // duplicado: si no está en valle, es pico.
      final valle = <Map<String, dynamic>>[];
      _clasificacion.forEach((key, tipo) {
        if (tipo != 'valle') return;
        final parts = key.split('|');
        if (parts.length != 2) return;
        final dia = int.tryParse(parts[0]);
        final hora = int.tryParse(parts[1]);
        if (dia == null || hora == null) return;
        valle.add({'dia': dia, 'hora': hora});
      });
      horariosConfig = {'valle': valle};
    }

    setState(() => _saving = true);
    try {
      // tipo_estudio se puede escribir directo; el modo, los créditos y la
      // grilla NO (el trigger estudios_bloquear_columnas_aura los protege),
      // así que van por RPC security definer.
      await _client
          .from('estudios')
          .update({'tipo_estudio': _tipoEstudio})
          .eq('id', widget.estudioId);

      await _client.rpc(
        'admin_set_pricing_estudio',
        params: {
          'p_estudio_id': widget.estudioId,
          'p_tipo_precio': _modo,
          'p_creditos_min': min,
          'p_creditos_max': _modo == 'fijo' ? min : max,
          'p_horarios_config': horariosConfig,
        },
      );

      // Recalcula TODAS las clases del estudio (pasadas incluidas) para que no
      // queden precios viejos mezclados.
      int recalculadas = 0;
      try {
        final res = await _client.rpc(
          'admin_recalcular_precios_estudio',
          params: {'p_estudio_id': widget.estudioId, 'p_incluir_pasadas': true},
        );
        recalculadas = (res as num?)?.toInt() ?? 0;
      } catch (_) {}

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            recalculadas > 0
                ? 'Configuración guardada. $recalculadas clase'
                      '${recalculadas == 1 ? '' : 's'} actualizada'
                      '${recalculadas == 1 ? '' : 's'}.'
                : 'Configuración guardada.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      _snack('No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cargarServicios() async {
    final rows = await _adminService.listServiciosPrecio(widget.estudioId);
    final catalogo = await _adminService.listStudyCategories();
    _servicios = rows
        .map(
          (r) => ServicioPrecio(
            servicio: r['servicio']?.toString() ?? '',
            creditos: (r['creditos'] as num?)?.toInt() ?? 0,
            activo: r['activo'] != false,
          ),
        )
        .where((s) => s.servicio.isNotEmpty)
        .toList();
    _catalogo = catalogo;
  }

  /// Alta o edición de un servicio: diálogo → PREVIEW en la base → cartel de
  /// confirmación con los números → aplicar → recargar.
  Future<void> _editarServicio({ServicioPrecio? existente}) async {
    final ya = _servicios.map((s) => s.servicio).toSet();
    final opciones = existente != null
        ? [existente.servicio]
        : _catalogo.where((c) => !ya.contains(c)).toList();
    if (opciones.isEmpty) {
      _snack(
        'Todas las categorías del catálogo ya tienen precio en este estudio.',
      );
      return;
    }

    final pedido = await showDialog<_ServicioPedido>(
      context: context,
      builder: (ctx) => _ServicioDialog(opciones: opciones, inicial: existente),
    );
    if (pedido == null || !mounted) return;

    setState(() => _guardandoServicio = true);
    try {
      final previewJson = await _adminService.setServicioPrecio(
        estudioId: widget.estudioId,
        servicio: pedido.servicio,
        creditos: pedido.creditos,
        activo: pedido.activo,
        soloPreview: true,
      );
      final preview = ServicioPreview.fromJson(previewJson);
      if (!mounted) return;

      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            tituloConfirmacionServicio(
              preview,
              widget.estudioNombre ?? 'el estudio',
            ),
          ),
          content: Text(
            mensajeConfirmacionServicio(preview),
            style: const TextStyle(height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'Aplicar',
                style: TextStyle(color: AppColors.primary),
              ),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;

      final aplicadoJson = await _adminService.setServicioPrecio(
        estudioId: widget.estudioId,
        servicio: pedido.servicio,
        creditos: pedido.creditos,
        activo: pedido.activo,
      );
      final aplicado = ServicioPreview.fromJson(aplicadoJson);
      await _cargarServicios();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(resumenAplicadoServicio(aplicado)),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      // El mensaje de la base es el que sirve (categoría inexistente, créditos
      // fuera de rango, sin permiso): se muestra tal cual.
      _snack('No se pudo guardar el servicio: ${_mensajeError(e)}');
    } finally {
      if (mounted) setState(() => _guardandoServicio = false);
    }
  }

  static String _mensajeError(Object e) {
    if (e is PostgrestException) return e.message;
    return e.toString();
  }

  Widget _buildServicios() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Servicios de precio fijo',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.black,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Una categoría con precio único para este estudio, sin franja '
          'horaria. Cambiar el precio sólo alcanza a las clases futuras sin '
          'reserva: lo ya reservado y lo pasado no se toca.',
          style: TextStyle(color: AppColors.grey, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 12),
        if (_servicios.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'Este estudio no tiene servicios de precio fijo.',
              style: TextStyle(color: AppColors.mutedText, fontSize: 13),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.warmBorder),
            ),
            child: Column(
              children: [
                for (var i = 0; i < _servicios.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, color: AppColors.warmBorder),
                  _ServicioRow(
                    servicio: _servicios[i],
                    onTap: widget.readOnly || _guardandoServicio
                        ? null
                        : () => _editarServicio(existente: _servicios[i]),
                  ),
                ],
              ],
            ),
          ),
        if (!widget.readOnly) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _guardandoServicio ? null : () => _editarServicio(),
            icon: const Icon(Icons.add, size: 18),
            label: Text(_guardandoServicio ? 'Guardando…' : 'Agregar servicio'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          widget.estudioNombre != null
              ? 'Precios — ${widget.estudioNombre}'
              : 'Precios del estudio',
        ),
      ),
      body: AnchoMaximo(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : _error != null
            ? Padding(
                padding: const EdgeInsets.all(20),
                child: Center(child: Text(_error!)),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildToggleTipo(),
                    const SizedBox(height: 20),
                    if (_tipoEstudio == 'fitness') ...[
                      _buildToggleModo(),
                      const SizedBox(height: 20),
                      _buildRangoFitness(),
                      if (_modo == 'rango') ...[
                        const SizedBox(height: 24),
                        _buildHorarios(),
                      ],
                    ] else
                      _buildPrecioExperiencia(),
                    const SizedBox(height: 28),
                    _buildServicios(),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _guardar,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          _saving ? 'Guardando…' : 'Guardar configuración',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildToggleTipo() {
    Widget option(String value, String label) {
      final selected = _tipoEstudio == value;
      return Expanded(
        child: GestureDetector(
          onTap: widget.readOnly
              ? null
              : () => setState(() => _tipoEstudio = value),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : AppColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppColors.primary : const Color(0xFFEDE7E1),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.white : AppColors.black,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tipo de estudio',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.black,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            option('fitness', 'Fitness'),
            const SizedBox(width: 10),
            option('experiencia', 'Experiencia'),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _tipoEstudio == 'fitness'
              ? 'Precio variable según día/hora (pico, normal y valle)'
              : 'Precio fijo, sin importar día/hora',
          style: const TextStyle(color: AppColors.grey, fontSize: 12),
        ),
      ],
    );
  }

  /// Selector del modo de precio. Es lo que decide si el estudio cobra un
  /// único valor o si el precio sale del horario (pico/valle).
  Widget _buildToggleModo() {
    Widget option(String value, String label) {
      final selected = _modo == value;
      return Expanded(
        child: GestureDetector(
          onTap: widget.readOnly ? null : () => setState(() => _modo = value),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : AppColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppColors.primary : const Color(0xFFEDE7E1),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.white : AppColors.black,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Modo de precio',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.black,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            option('fijo', 'Precio fijo'),
            const SizedBox(width: 10),
            option('rango', 'Precio por rango'),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _modo == 'fijo'
              ? 'Todas las clases del estudio valen lo mismo, sin importar el '
                    'día ni la hora.'
              : 'El precio sale del horario: marcás los flojos como valle '
                    '(mínimo) y el resto es pico (máximo).',
          style: const TextStyle(
            color: AppColors.grey,
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _buildRangoFitness() {
    final esFijo = _modo == 'fijo';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          esFijo ? 'Precio del estudio' : 'Rango de precio del estudio',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.black,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          esFijo
              ? 'Créditos que cuesta cada clase de este estudio. El estudio no '
                    'lo puede editar.'
              : 'Rango negociado en créditos. En los horarios que marques como '
                    'valle la clase cuesta el mínimo; en todos los demás, el '
                    'máximo.',
          style: const TextStyle(
            color: AppColors.grey,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        if (esFijo)
          TextField(
            controller: _minCtrl,
            enabled: !widget.readOnly,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Créditos por clase',
              suffixText: 'cr',
              isDense: true,
              prefixIcon: Icon(
                Icons.local_activity_outlined,
                color: AppColors.primary,
                size: 18,
              ),
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _minCtrl,
                  enabled: !widget.readOnly,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Mínimo (valle)',
                    suffixText: 'cr',
                    isDense: true,
                    prefixIcon: Icon(Icons.south, color: _valleColor, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _maxCtrl,
                  enabled: !widget.readOnly,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Máximo (pico)',
                    suffixText: 'cr',
                    isDense: true,
                    prefixIcon: Icon(Icons.bolt, color: _picoColor, size: 18),
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        _buildPreviewIngreso(),
      ],
    );
  }

  Widget _buildPreviewIngreso() {
    final min = int.tryParse(_minCtrl.text.trim());
    // En modo fijo el techo es el mismo valor: no hay rango que mostrar.
    final max = _modo == 'fijo' ? min : int.tryParse(_maxCtrl.text.trim());
    final String texto;
    if (min == null && max == null) {
      texto = _modo == 'fijo'
          ? 'Completá el precio para ver cuánto recibe el estudio por clase.'
          : 'Completá el rango para ver cuánto recibe el estudio por clase.';
    } else {
      final lo = min ?? max!;
      final hi = max ?? min!;
      final recibeLo = _pricingService.montoEstudioPorClase(
        _valorCredito,
        lo,
        _comisionAura,
      );
      final recibeHi = _pricingService.montoEstudioPorClase(
        _valorCredito,
        hi,
        _comisionAura,
      );
      texto = recibeLo == recibeHi
          ? 'Estudio recibe ${_fmtPesos(recibeLo)} por clase'
          : 'Estudio recibe entre ${_fmtPesos(recibeLo)} y '
                '${_fmtPesos(recibeHi)} por clase';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1E8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.payments_outlined,
            color: AppColors.primary,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHorarios() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Horarios pico y valle',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.black,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Marcá los horarios FLOJOS: esos cobran el mínimo. Todo lo que dejes '
          'sin marcar es horario pico y cobra el máximo. Cada franja es de una '
          'hora y se marca por separado.',
          style: TextStyle(color: AppColors.grey, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _LeyendaFranja(color: _valleColor, texto: '🌙 Valle (mínimo)'),
            const SizedBox(width: 14),
            _LeyendaFranja(
              color: AppColors.white,
              texto: '⚡ Pico (máximo)',
              borde: true,
            ),
          ],
        ),
        const SizedBox(height: 14),
        for (int dia = 1; dia <= 7; dia++) _buildDiaRow(dia),
      ],
    );
  }

  Widget _buildDiaRow(int dia) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _diasSemana[dia],
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.black,
                ),
              ),
              const Spacer(),
              // Atajos por día: marcar todo el día como valle o limpiarlo.
              // Con 18 franjas por día, hacerlo chip por chip es tedioso.
              if (!widget.readOnly) ...[
                _AccionDia(
                  texto: 'Todo valle',
                  onTap: () => _marcarDia(dia, true),
                ),
                const SizedBox(width: 10),
                _AccionDia(
                  texto: 'Limpiar',
                  onTap: () => _marcarDia(dia, false),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: kHorasGrilla.map((hora) {
              final key = '$dia|$hora';
              final esValle = _clasificacion[key] == 'valle';
              return GestureDetector(
                onTap: widget.readOnly ? null : () => _toggleValle(key),
                child: Container(
                  width: 62,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: esValle ? _valleColor : AppColors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: esValle ? _valleColor : const Color(0xFFEDE7E1),
                    ),
                  ),
                  child: Text(
                    horaLabel(hora),
                    style: TextStyle(
                      color: esValle ? AppColors.white : AppColors.black,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// Dos estados nomás: valle o pico. Tocar alterna; lo no marcado es pico.
  void _toggleValle(String key) {
    setState(() {
      if (_clasificacion[key] == 'valle') {
        _clasificacion.remove(key);
      } else {
        _clasificacion[key] = 'valle';
      }
    });
  }

  void _marcarDia(int dia, bool valle) {
    setState(() {
      for (final hora in kHorasGrilla) {
        final key = '$dia|$hora';
        if (valle) {
          _clasificacion[key] = 'valle';
        } else {
          _clasificacion.remove(key);
        }
      }
    });
  }

  Widget _buildPrecioExperiencia() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Comisión de workshops',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.black,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'El precio en créditos lo define el estudio en cada workshop.',
          style: TextStyle(color: AppColors.grey, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _comisionWorkshopCtrl,
          enabled: !widget.readOnly,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Comisión workshops (%)',
            helperText: 'Porcentaje que retiene Aura en workshops. Default 15.',
            suffixText: '%',
            isDense: true,
          ),
        ),
      ],
    );
  }

  static int? _asInt(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  static String _fmtPesos(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '\$$buf';
  }
}

/// Cuadradito de color + texto, para la referencia de la grilla.
class _LeyendaFranja extends StatelessWidget {
  final Color color;
  final String texto;
  final bool borde;
  const _LeyendaFranja({
    required this.color,
    required this.texto,
    this.borde = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            border: borde ? Border.all(color: const Color(0xFFEDE7E1)) : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          texto,
          style: const TextStyle(color: AppColors.grey, fontSize: 12),
        ),
      ],
    );
  }
}

/// Atajo de texto al lado del nombre del día ("Todo valle" / "Limpiar").
/// Con 18 franjas por día, marcarlas de a una es tedioso.
class _AccionDia extends StatelessWidget {
  final String texto;
  final VoidCallback onTap;
  const _AccionDia({required this.texto, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        texto,
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── Servicios de precio fijo: fila y diálogo ─────────────────────────────────

class _ServicioRow extends StatelessWidget {
  final ServicioPrecio servicio;
  final VoidCallback? onTap;

  const _ServicioRow({required this.servicio, this.onTap});

  @override
  Widget build(BuildContext context) {
    final activo = servicio.activo;
    return ListTile(
      onTap: onTap,
      dense: true,
      title: Text(
        servicio.servicio,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: activo ? AppColors.black : AppColors.grey,
        ),
      ),
      subtitle: Text(
        activo ? 'Activo' : 'Inactivo',
        style: TextStyle(
          fontSize: 12,
          color: activo ? AppColors.success : AppColors.mutedText,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: activo ? AppColors.primaryLight : AppColors.lightGrey,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              servicio.creditos == 0 ? 'GRATIS' : '${servicio.creditos} cr',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: activo ? AppColors.primary : AppColors.grey,
              ),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            const Icon(Icons.edit_outlined, size: 18, color: AppColors.grey),
          ],
        ],
      ),
    );
  }
}

class _ServicioPedido {
  final String servicio;
  final int creditos;
  final bool activo;
  const _ServicioPedido(this.servicio, this.creditos, this.activo);
}

/// Lo mínimo: elegir la categoría del catálogo, el precio, y activar o no.
/// La validación de verdad la hace la base (rango 0..500, categoría activa,
/// permiso): acá sólo se evita mandar basura obvia.
class _ServicioDialog extends StatefulWidget {
  final List<String> opciones;
  final ServicioPrecio? inicial;

  const _ServicioDialog({required this.opciones, this.inicial});

  @override
  State<_ServicioDialog> createState() => _ServicioDialogState();
}

class _ServicioDialogState extends State<_ServicioDialog> {
  late String _servicio;
  late final TextEditingController _creditosCtrl;
  late bool _activo;
  String? _error;

  @override
  void initState() {
    super.initState();
    _servicio = widget.inicial?.servicio ?? widget.opciones.first;
    _creditosCtrl = TextEditingController(
      text: widget.inicial?.creditos.toString() ?? '',
    );
    _activo = widget.inicial?.activo ?? true;
  }

  @override
  void dispose() {
    _creditosCtrl.dispose();
    super.dispose();
  }

  void _confirmar() {
    final n = int.tryParse(_creditosCtrl.text.trim());
    if (n == null || n < 0 || n > 500) {
      setState(() => _error = 'Créditos entre 0 y 500. 0 es gratis.');
      return;
    }
    Navigator.pop(context, _ServicioPedido(_servicio, n, _activo));
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.inicial != null;
    return AlertDialog(
      title: Text(
        editando ? 'Editar servicio' : 'Nuevo servicio de precio fijo',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            // Al editar la categoría no se cambia: es la clave de la fila.
            initialValue: _servicio,
            items: [
              for (final o in widget.opciones)
                DropdownMenuItem(value: o, child: Text(o)),
            ],
            onChanged: editando
                ? null
                : (v) => setState(() => _servicio = v ?? _servicio),
            decoration: const InputDecoration(
              labelText: 'Categoría del catálogo',
              isDense: true,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _creditosCtrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _confirmar(),
            decoration: InputDecoration(
              labelText: 'Créditos',
              suffixText: 'cr',
              helperText: '0 = gratis (por ejemplo, Running club)',
              errorText: _error,
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Activo'),
            subtitle: const Text(
              'Inactivo: las clases ya cargadas conservan su precio.',
              style: TextStyle(fontSize: 12),
            ),
            value: _activo,
            activeThumbColor: AppColors.primary,
            onChanged: (v) => setState(() => _activo = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: _confirmar,
          child: const Text(
            'Continuar',
            style: TextStyle(color: AppColors.primary),
          ),
        ),
      ],
    );
  }
}
