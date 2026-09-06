import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/valor_credito.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../utils/liquidacion.dart';
import '../../utils/mes_argentino.dart';
import '../../utils/datos_cobro.dart';
import '../../services/admin_service.dart';
import '../../widgets/ancho_maximo.dart';

class AdminLiquidacionesScreen extends StatefulWidget {
  const AdminLiquidacionesScreen({super.key});

  @override
  State<AdminLiquidacionesScreen> createState() =>
      _AdminLiquidacionesScreenState();
}

class _AdminLiquidacionesScreenState extends State<AdminLiquidacionesScreen> {
  final _client = Supabase.instance.client;
  final _adminService = AdminService();

  // Últimos 6 meses (más reciente primero)
  late List<String> _meses;
  late String _mesSeleccionado;

  bool _loading = true;
  bool _enviandoAviso = false;
  bool _enviandoReporte = false;
  String? _error;

  // Por estudio: { estudio_id, nombre, cantidad_reservas, monto_total, monto_pagar, estado, fecha_pago, comprobante_nota }
  List<Map<String, dynamic>> _estudios = [];

  // Lo que se debe de meses cerrados, sin importar el selector.
  List<Map<String, dynamic>> _pendientes = [];

  // Historial expandido
  bool _historialExpanded = false;
  bool _loadingHistorial = false;
  List<Map<String, dynamic>> _historial = [];

  @override
  void initState() {
    super.initState();
    _meses = _ultimos6Meses();
    _mesSeleccionado = _meses.first;
    _cargar();
  }

  // ── Helpers de fecha ─────────────────────────────────────────────────────

  List<String> _ultimos6Meses() {
    final now = DateTime.now();
    return List.generate(6, (i) {
      final d = DateTime(now.year, now.month - i, 1);
      return '${d.year}-${d.month.toString().padLeft(2, '0')}';
    });
  }

  DateTime _inicioMes(String mes) {
    final parts = mes.split('-');
    return DateTime(int.parse(parts[0]), int.parse(parts[1]), 1);
  }

  String _labelMes(String mes) {
    final d = _inicioMes(mes);
    return DateFormat("MMMM yyyy", 'es').format(d);
  }

  // ── Data loading ─────────────────────────────────────────────────────────

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resultado = await _calcularMes(_mesSeleccionado);
      if (!mounted) return;
      setState(() {
        _estudios = resultado;
        _loading = false;
      });
      // Los pendientes de TODOS los meses cerrados, aparte del selector.
      await _cargarPendientes();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  /// Lo que Aura le debe a cada estudio por [mes], con la MISMA fórmula que
  /// Cobros y Dashboard (`Liquidacion.netoReserva`). Devuelve sólo estudios
  /// con reservas, con su liquidación registrada si la hay.
  ///
  /// Era el cuerpo de `_cargar`. Se separó (6/9/2026) para poder correrlo
  /// sobre varios meses: la pantalla abría siempre en el mes ACTUAL, y lo que
  /// se debe es del mes ANTERIOR, así que la deuda quedaba escondida detrás
  /// del selector. Con la primera facturación real (Citra, agosto), Sofía
  /// abrió el backoffice en septiembre, lo vio vacío y creyó que los
  /// pendientes habían desaparecido.
  Future<List<Map<String, dynamic>>> _calcularMes(String mes) async {
    // Corte por MES CALENDARIO ARGENTINO (2/9). Antes el rango se armaba
    // con DateTime local sin zona y Postgres lo leía como UTC: las reservas
    // de 21:00 a 23:59 del último día caían en el mes siguiente. Además el
    // fin era `lte 23:59:59`, que dejaba una grieta de sub-segundo donde
    // una reserva no caía en NINGÚN mes: ahora es exclusivo (lt).
    final limites = limitesMesArgentino(mes);
    final inicio = limites.inicioUtc.toIso8601String();
    final finExclusivo = limites.finExclusivoUtc.toIso8601String();

    // 1. Traer reservas del mes con el estudio (via clase). reservas no tiene
    // columna estudio_id: se obtiene de clases.estudio_id. Join explícito con
    // el hint de FK para que PostgREST resuelva la relación (evita PGRST200).
    final reservas = await _client
        .from('reservas')
        .select(
          'estado, creditos_usados, clases!reservas_clase_id_fkey(estudio_id, tipo)',
        )
        .inFilter('estado', AppConstants.estadosLiquidables)
        .gte('created_at', inicio)
        .lt('created_at', finExclusivo);

    // 2. Traer todos los estudios activos (con comisión + fecha inicio cobro)
    // comision_aura / comision_workshop / valor_credito viven en
    // estudios_datos_cobro; fecha_inicio_cobro sigue en estudios.
    // Se aplanan para que Liquidacion.* reciba la misma forma de mapa.
    final estudiosRaw = await _client
        .from('estudios')
        .select(
          'id, nombre, fecha_inicio_cobro, '
          'estudios_datos_cobro(comision_aura, comision_workshop, valor_credito)',
        )
        .eq('activo', true)
        .order('nombre');
    final estudiosData = DatosCobro.aplanarLista(estudiosRaw as List);

    // 3. Traer liquidaciones ya registradas para este mes
    final liquidaciones = await _client
        .from('liquidaciones')
        .select()
        .eq('mes', mes);

    // 4. Índice de estudios (trae comisión, valor_credito, fecha_inicio_cobro)
    final Map<int, Map<String, dynamic>> estudioPorId = {
      for (final e in (estudiosData as List))
        (e['id'] as num).toInt(): Map<String, dynamic>.from(e as Map),
    };

    // 5. Neto por estudio, usando la MISMA fórmula que Cobros y Dashboard
    // (Liquidacion.netoReserva): valor_credito del estudio, comisión por
    // tipo, y fecha_inicio_cobro. Así las tres pantallas dan el mismo número.
    final Map<int, int> montoPagarPorEstudio = {};
    final Map<int, int> montoBrutoPorEstudio = {};
    final Map<int, int> reservasPorEstudio = {};

    for (final r in (reservas as List)) {
      final clase = r['clases'] as Map<String, dynamic>?;
      final esId = (clase?['estudio_id'] as num?)?.toInt();
      if (esId == null) continue;
      final estudio = estudioPorId[esId];

      // Reserva aplanada como la esperan los helpers.
      final reservaPlana = <String, dynamic>{
        'estado': r['estado'],
        'creditos_usados': r['creditos_usados'],
        '_clase_tipo': clase?['tipo'],
      };
      final cred = (r['creditos_usados'] as num?)?.toInt() ?? 0;

      montoPagarPorEstudio[esId] =
          (montoPagarPorEstudio[esId] ?? 0) +
          Liquidacion.netoReserva(reservaPlana, estudio);
      montoBrutoPorEstudio[esId] =
          (montoBrutoPorEstudio[esId] ?? 0) +
          cred * ValorCredito.deEstudio(estudio);
      reservasPorEstudio[esId] = (reservasPorEstudio[esId] ?? 0) + 1;
    }

    // Mapa de liquidaciones registradas
    final Map<int, Map<String, dynamic>> liqMap = {};
    for (final l in (liquidaciones as List)) {
      final esId = (l['estudio_id'] as num?)?.toInt();
      if (esId != null) liqMap[esId] = Map<String, dynamic>.from(l);
    }

    // 6. Construir lista solo de estudios con reservas
    final List<Map<String, dynamic>> resultado = [];
    for (final e in estudioPorId.values) {
      final esId = (e['id'] as num).toInt();
      final cantReservas = reservasPorEstudio[esId] ?? 0;
      if (cantReservas == 0) continue;

      final montoTotal = montoBrutoPorEstudio[esId] ?? 0;
      final montoPagar = montoPagarPorEstudio[esId] ?? 0;
      // Comisión efectiva derivada de los montos reales (promedio ponderado
      // para estudios con clases + workshops).
      final comisionPct = montoTotal > 0
          ? (montoTotal - montoPagar) / montoTotal * 100
          : Liquidacion.comision(e, esWorkshop: false);

      final liq = liqMap[esId];
      resultado.add({
        'estudio_id': esId,
        'nombre': e['nombre']?.toString() ?? 'Estudio',
        'mes': mes,
        'cantidad_reservas': cantReservas,
        'monto_total': montoTotal,
        'monto_pagar': montoPagar,
        'comision_pct': comisionPct,
        'estado': liq?['estado'] ?? 'pendiente',
        'fecha_pago': liq?['fecha_pago'],
        'comprobante_nota': liq?['comprobante_nota'],
        'liquidacion_id': liq?['id'],
      });
    }

    // Ordenar: pendientes primero, luego por monto desc
    resultado.sort((a, b) {
      final aPend = a['estado'] == 'pendiente' ? 0 : 1;
      final bPend = b['estado'] == 'pendiente' ? 0 : 1;
      if (aPend != bPend) return aPend - bPend;
      return (b['monto_pagar'] as int).compareTo(a['monto_pagar'] as int);
    });
    return resultado;
  }

  /// TODO lo que Aura debe: cada estudio con reservas en un mes CERRADO que
  /// no tenga liquidación pagada. No depende del selector. Es la lista que
  /// Sofía necesita ver siempre arriba, hasta que lo pague.
  ///
  /// Un mes cerrado sin ninguna fila en `liquidaciones` también cuenta: es
  /// exactamente el caso que se escondía (Citra, agosto).
  Future<void> _cargarPendientes() async {
    final mesActual = mesArgentinoDe(DateTime.now());
    final cerrados = _meses.where((m) => m != mesActual).toList();
    final List<Map<String, dynamic>> deuda = [];
    for (final mes in cerrados) {
      final filas = await _calcularMes(mes);
      deuda.addAll(filas.where((f) => f['estado'] != 'pagado'));
    }
    if (!mounted) return;
    setState(() => _pendientes = deuda);
  }

  Future<void> _cargarHistorial() async {
    setState(() => _loadingHistorial = true);
    try {
      // Todos los meses anteriores al seleccionado
      final mesesAnteriores = _meses.skip(1).toList();
      if (mesesAnteriores.isEmpty) {
        if (mounted) setState(() => _loadingHistorial = false);
        return;
      }

      final List<Map<String, dynamic>> resumen = [];
      for (final mes in mesesAnteriores) {
        final liqMes = await _client
            .from('liquidaciones')
            .select('estado, monto_a_pagar')
            .eq('mes', mes);

        final lista = liqMes as List;
        if (lista.isEmpty) continue;
        final totalPagado = lista.fold<int>(
          0,
          (acc, l) => acc + ((l['monto_a_pagar'] as num?)?.toInt() ?? 0),
        );
        final cantEstudios = lista.length;
        final completado = lista.every(
          (l) => l['estado']?.toString() == 'pagado',
        );
        resumen.add({
          'mes': mes,
          'total_pagado': totalPagado,
          'cantidad_estudios': cantEstudios,
          'completado': completado,
        });
      }

      if (!mounted) return;
      setState(() {
        _historial = resumen;
        _loadingHistorial = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingHistorial = false);
    }
  }

  // ── Registrar pago ───────────────────────────────────────────────────────

  Future<void> _registrarPago(Map<String, dynamic> estudio, String nota) async {
    final esId = estudio['estudio_id'] as int;
    final montoPagar = estudio['monto_pagar'] as int;
    final montoTotal = estudio['monto_total'] as int;
    final cantReservas = estudio['cantidad_reservas'] as int;
    final liqId = estudio['liquidacion_id'] as String?;

    try {
      if (liqId != null) {
        await _client
            .from('liquidaciones')
            .update({
              'estado': 'pagado',
              'fecha_pago': DateTime.now().toIso8601String(),
              'comprobante_nota': nota.trim().isEmpty ? null : nota.trim(),
            })
            .eq('id', liqId);
      } else {
        await _client.from('liquidaciones').insert({
          'estudio_id': esId,
          // El mes de la FILA, no el del selector: desde "Pendientes" se paga
          // un mes que no es el seleccionado.
          'mes': (estudio['mes'] as String?) ?? _mesSeleccionado,
          'monto_total_reservas': montoTotal,
          'monto_a_pagar': montoPagar,
          'cantidad_reservas': cantReservas,
          'estado': 'pagado',
          'fecha_pago': DateTime.now().toIso8601String(),
          'comprobante_nota': nota.trim().isEmpty ? null : nota.trim(),
        });
      }

      if (!mounted) return;
      // La fila pagada sale de "Pendientes" en el acto.
      setState(() {
        _pendientes.removeWhere(
          (p) => p['estudio_id'] == esId && p['mes'] == estudio['mes'],
        );
        final idx = _estudios.indexWhere((e) => e['estudio_id'] == esId);
        if (idx >= 0) {
          _estudios[idx] = {
            ..._estudios[idx],
            'estado': 'pagado',
            'fecha_pago': DateTime.now().toIso8601String(),
            'comprobante_nota': nota.trim().isEmpty ? null : nota.trim(),
          };
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Pago registrado correctamente'),
          backgroundColor: const Color(0xFF1A1A1A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _enviarAvisoCobro() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar aviso de cobro'),
        content: const Text(
          '¿Querés enviar el email de aviso a todos los estudios con reservas este mes?\n\nSolo se envía a estudios con monto > \$0.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Enviar',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _enviandoAviso = true);
    try {
      final result = await _adminService.enviarAvisoCobro();
      if (!mounted) return;
      final enviados = result['enviados'] as int? ?? 0;
      final errores = result['errores'] as int? ?? 0;
      final omitidos = result['omitidos'] as int? ?? 0;
      final msg = errores == 0
          ? '✓ $enviados aviso${enviados != 1 ? 's' : ''} enviado${enviados != 1 ? 's' : ''}. $omitidos sin reservas.'
          : '$enviados enviados · $errores con error · $omitidos sin reservas.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: errores == 0
              ? const Color(0xFF1A1A1A)
              : AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _enviandoAviso = false);
    }
  }

  Future<void> _enviarReporteMensual() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar reporte mensual'),
        content: const Text(
          '¿Querés enviar el reporte mensual a todos los estudios con reservas el mes pasado?\n\nSolo se envía a estudios con actividad.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Enviar',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _enviandoReporte = true);
    try {
      final result = await _adminService.enviarReporteMensual();
      if (!mounted) return;
      final enviados = result['enviados'] as int? ?? 0;
      final errores = result['errores'] as int? ?? 0;
      final omitidos = result['omitidos'] as int? ?? 0;
      final msg = errores == 0
          ? '✓ $enviados reporte${enviados != 1 ? 's' : ''} enviado${enviados != 1 ? 's' : ''}. $omitidos sin actividad.'
          : '$enviados enviados · $errores con error · $omitidos sin actividad.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: errores == 0
              ? const Color(0xFF1A1A1A)
              : AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _enviandoReporte = false);
    }
  }

  void _abrirBottomSheet(Map<String, dynamic> estudio) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _PagoSheet(
        estudio: estudio,
        onConfirmar: (nota) async {
          Navigator.pop(ctx);
          await _registrarPago(estudio, nota);
        },
      ),
    );
  }

  // ── Formateo ─────────────────────────────────────────────────────────────

  static String _fmt(int amount) {
    final s = amount.toString();
    final buf = StringBuffer('\$');
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F5F2),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Liquidaciones',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A1A),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _mesSeleccionado,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                items: _meses.map((mes) {
                  return DropdownMenuItem(
                    value: mes,
                    child: Text(_labelMes(mes)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val == null || val == _mesSeleccionado) return;
                  setState(() => _mesSeleccionado = val);
                  _cargar();
                },
              ),
            ),
          ),
        ],
      ),
      body: AnchoMaximo(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : _error != null
            ? _buildError()
            : RefreshIndicator(
                onRefresh: _cargar,
                child: ListView(
                  children: [
                    const SizedBox(height: 16),
                    // Lo que se debe, SIEMPRE arriba y sin depender del
                    // selector de mes. Ver `_cargarPendientes`.
                    _buildPendientesSection(),
                    _buildResumenCard(),
                    const SizedBox(height: 20),
                    ..._estudios.map(_buildEstudioCard),
                    const SizedBox(height: 24),
                    _buildHistorialSection(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildPendientesSection() {
    final total = _pendientes.fold<int>(
      0,
      (acc, e) => acc + (e['monto_pagar'] as int),
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      decoration: BoxDecoration(
        color: _pendientes.isEmpty
            ? const Color(0xFFE3F3E5)
            : const Color(0xFFFFF3DE),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _pendientes.isEmpty
                    ? Icons.check_circle_outline_rounded
                    : Icons.pending_actions_rounded,
                size: 20,
                color: _pendientes.isEmpty
                    ? const Color(0xFF43A047)
                    : AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _pendientes.isEmpty
                      ? 'No debés nada de meses cerrados'
                      : 'Pendiente de pago · ${_fmt(total)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          if (_pendientes.isEmpty)
            const SizedBox(height: 10)
          else ...[
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 10),
              child: Text(
                'Meses cerrados sin pagar, de todos los estudios. '
                'Desaparecen de acá cuando tocás "Registrar pago".',
                style: TextStyle(color: Color(0xFF8F877F), fontSize: 12),
              ),
            ),
            // La tarjeta trae su propio margen lateral de 20 y acá ya está
            // dentro de una caja con padding: se lo compensa para que quede
            // alineada con el título.
            ..._pendientes.map(
              (e) => Transform.translate(
                offset: const Offset(-4, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: _buildEstudioCard(e, margenLateral: 4),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: AppColors.grey,
            ),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _cargar, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }

  Widget _buildResumenCard() {
    final pendientes = _estudios
        .where((e) => e['estado'] == 'pendiente')
        .toList();
    final totalPendiente = pendientes.fold<int>(
      0,
      (acc, e) => acc + (e['monto_pagar'] as int),
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Total a pagar este mes',
                  style: TextStyle(color: Color(0xFFF5F0EB), fontSize: 14),
                ),
              ),
              Text(
                _fmt(totalPendiente),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${pendientes.length} estudio${pendientes.length != 1 ? 's' : ''} pendiente${pendientes.length != 1 ? 's' : ''}',
            style: const TextStyle(color: Color(0xFF8F877F), fontSize: 13),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _enviandoAviso ? null : _enviarAvisoCobro,
              icon: _enviandoAviso
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.send_rounded, size: 16),
              label: Text(
                _enviandoAviso
                    ? 'Enviando...'
                    : 'Enviar aviso de cobro manualmente',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _enviandoReporte ? null : _enviarReporteMensual,
              icon: _enviandoReporte
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.bar_chart_rounded, size: 16),
              label: Text(
                _enviandoReporte
                    ? 'Enviando...'
                    : 'Enviar reporte mensual manualmente',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2A2A2A),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEstudioCard(
    Map<String, dynamic> estudio, {
    double margenLateral = 20,
  }) {
    final nombre = estudio['nombre'] as String;
    final cantReservas = estudio['cantidad_reservas'] as int;
    final montoPagar = estudio['monto_pagar'] as int;
    final estado = estudio['estado'] as String;
    final pagado = estado == 'pagado';

    final inicial = nombre.isNotEmpty ? nombre[0].toUpperCase() : '?';

    return Container(
      margin: EdgeInsets.fromLTRB(margenLateral, 0, margenLateral, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // Row superior
          Row(
            children: [
              // Avatar
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    inicial,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // En "Pendientes" la fila puede ser de otro mes que el
                      // del selector: hay que decir cuál.
                      estudio['mes'] == _mesSeleccionado
                          ? '$cantReservas reserva${cantReservas != 1 ? 's' : ''} este mes'
                          : '$cantReservas reserva${cantReservas != 1 ? 's' : ''} · ${_labelMes(estudio['mes'] as String)}',
                      style: const TextStyle(
                        color: Color(0xFF8F877F),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Badge estado
              _EstadoBadge(pagado: pagado),
            ],
          ),

          // Row inferior (solo si pendiente)
          if (!pagado) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFF0EDE8)),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  _fmt(montoPagar),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _abrirBottomSheet(estudio),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Registrar pago',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistorialSection() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GestureDetector(
            onTap: () {
              if (!_historialExpanded) {
                _cargarHistorial();
              }
              setState(() => _historialExpanded = !_historialExpanded);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.history_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _historialExpanded ? 'Ocultar historial' : 'Ver historial',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _historialExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_historialExpanded) ...[
          const SizedBox(height: 12),
          if (_loadingHistorial)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2,
              ),
            )
          else if (_historial.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Text(
                'No hay meses anteriores registrados.',
                style: TextStyle(color: AppColors.grey),
                textAlign: TextAlign.center,
              ),
            )
          else
            ..._historial.map(_buildHistorialCard),
        ],
      ],
    );
  }

  Widget _buildHistorialCard(Map<String, dynamic> item) {
    final mes = item['mes'] as String;
    final totalPagado = item['total_pagado'] as int;
    final cantEstudios = item['cantidad_estudios'] as int;
    final completado = item['completado'] as bool;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _labelMes(mes),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$cantEstudios estudio${cantEstudios != 1 ? 's' : ''} · ${_fmt(totalPagado)} pagado${completado ? '' : ' (parcial)'}',
                  style: const TextStyle(
                    color: Color(0xFF8F877F),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (completado)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Completado',
                style: TextStyle(
                  color: Color(0xFF2E7D32),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Parcial',
                style: TextStyle(
                  color: Color(0xFFE65100),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Supporting widgets ─────────────────────────────────────────────────────────

class _EstadoBadge extends StatelessWidget {
  final bool pagado;

  const _EstadoBadge({required this.pagado});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: pagado ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        pagado ? 'PAGADO' : 'PENDIENTE',
        style: TextStyle(
          color: pagado ? const Color(0xFF2E7D32) : const Color(0xFFE65100),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _PagoSheet extends StatefulWidget {
  final Map<String, dynamic> estudio;
  final Future<void> Function(String nota) onConfirmar;

  const _PagoSheet({required this.estudio, required this.onConfirmar});

  @override
  State<_PagoSheet> createState() => _PagoSheetState();
}

class _PagoSheetState extends State<_PagoSheet> {
  final _notaCtrl = TextEditingController();
  bool _confirmando = false;

  static String _fmt(int amount) {
    final s = amount.toString();
    final buf = StringBuffer('\$');
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  void dispose() {
    _notaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nombre = widget.estudio['nombre'] as String;
    final montoPagar = widget.estudio['monto_pagar'] as int;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFDDD8D2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Registrar pago a $nombre',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 16),
            // Monto grande
            Center(
              child: Text(
                _fmt(montoPagar),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Campo nota
            const Text(
              'Nota o comprobante',
              style: TextStyle(
                color: Color(0xFF5F5953),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notaCtrl,
              maxLines: 3,
              style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A1A)),
              decoration: InputDecoration(
                hintText: 'Ej: Transferencia CBU 1234, comprobante MP #XXXXX',
                hintStyle: const TextStyle(
                  color: Color(0xFF9A928B),
                  fontSize: 14,
                ),
                filled: true,
                fillColor: const Color(0xFFF7F5F2),
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Botón confirmar
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _confirmando
                    ? null
                    : () async {
                        setState(() => _confirmando = true);
                        await widget.onConfirmar(_notaCtrl.text);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _confirmando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Confirmar pago',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            // Botón cancelar
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  foregroundColor: const Color(0xFF8F877F),
                ),
                child: const Text('Cancelar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
