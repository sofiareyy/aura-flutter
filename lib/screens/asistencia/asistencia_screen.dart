import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';

class AsistenciaScreen extends StatefulWidget {
  const AsistenciaScreen({super.key});

  @override
  State<AsistenciaScreen> createState() => _AsistenciaScreenState();
}

class _AsistenciaScreenState extends State<AsistenciaScreen> {
  List<Map<String, dynamic>> _clases = [];
  List<Map<String, dynamic>> _asistentes = [];
  Map<String, dynamic>? _claseSeleccionada;
  bool _loading = true;
  DateTime _now = DateTime.now();
  Timer? _bannerTimer;

  // Scanner
  late bool _usarCamara;
  bool _procesando = false;
  final _qrController = TextEditingController();
  final _qrFocusNode = FocusNode();
  MobileScannerController? _cameraController;

  @override
  void initState() {
    super.initState();
    _usarCamara = !kIsWeb;
    if (_usarCamara) _cameraController = MobileScannerController();
    _cargar();
    _bannerTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _qrController.dispose();
    _qrFocusNode.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final now = DateTime.now();
    final clases = await Supabase.instance.client
        .from('clases')
        .select()
        .gte('fecha', DateTime(now.year, now.month, now.day).toIso8601String())
        .order('fecha')
        .limit(10);

    final mapped = List<Map<String, dynamic>>.from(clases as List);
    final selected = mapped.isNotEmpty ? mapped.first : null;
    final attendees = await _cargarAsistentes(selected);

    if (!mounted) return;
    setState(() {
      _clases = mapped;
      _claseSeleccionada = selected;
      _asistentes = attendees;
      _loading = false;
    });
  }

  Future<List<Map<String, dynamic>>> _cargarAsistentes(
    Map<String, dynamic>? clase,
  ) async {
    if (clase == null) return [];
    final reservas = await Supabase.instance.client
        .from('reservas')
        .select()
        .eq('clase_id', clase['id'])
        .neq('estado', 'cancelada');

    final result = <Map<String, dynamic>>[];
    for (final r in (reservas as List)) {
      final usuario = await Supabase.instance.client
          .from('usuarios')
          .select('nombre,email')
          .eq('id', r['usuario_id'])
          .maybeSingle();
      result.add({
        ...Map<String, dynamic>.from(r),
        'usuario': usuario,
      });
    }
    return result;
  }

  Future<void> _seleccionarClase(Map<String, dynamic> clase) async {
    setState(() => _loading = true);
    final attendees = await _cargarAsistentes(clase);
    if (!mounted) return;
    setState(() {
      _claseSeleccionada = clase;
      _asistentes = attendees;
      _loading = false;
    });
  }

  // ── QR validation ────────────────────────────────────────────────────────

  Future<void> _validarQR(String codigo) async {
    if (_procesando || codigo.trim().isEmpty) return;
    setState(() => _procesando = true);

    try {
      final reserva = await Supabase.instance.client
          .from('reservas')
          .select()
          .eq('codigo_qr', codigo.trim())
          .neq('estado', 'cancelada')
          .maybeSingle();

      if (!mounted) return;

      if (reserva == null) {
        _mostrarPopup(exito: false, titulo: 'QR inválido', subtitulo: 'No se encontró una reserva activa');
        return;
      }

      final usuario = await Supabase.instance.client
          .from('usuarios')
          .select('nombre')
          .eq('id', reserva['usuario_id'])
          .maybeSingle();

      final clase = await Supabase.instance.client
          .from('clases')
          .select('nombre')
          .eq('id', reserva['clase_id'])
          .maybeSingle();

      await Supabase.instance.client.from('reservas').update({
        'estado': 'presente',
        'checked_in_at': DateTime.now().toIso8601String(),
      }).eq('codigo_qr', codigo.trim());

      if (!mounted) return;

      _mostrarPopup(
        exito: true,
        titulo: usuario?['nombre']?.toString() ?? 'Usuario',
        subtitulo: clase?['nombre']?.toString() ?? 'Clase',
      );

      _cargarAsistentes(_claseSeleccionada).then((list) {
        if (mounted) setState(() => _asistentes = list);
      });
    } catch (_) {
      if (mounted) {
        _mostrarPopup(exito: false, titulo: 'Error', subtitulo: 'Intentá de nuevo');
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  void _mostrarPopup({
    required bool exito,
    required String titulo,
    required String subtitulo,
  }) {
    _cameraController?.stop();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ResultPopup(exito: exito, titulo: titulo, subtitulo: subtitulo),
    ).then((_) {
      if (_usarCamara) {
        _cameraController?.start();
      } else {
        _qrFocusNode.requestFocus();
      }
    });

    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    });
  }

  void _cambiarModo() {
    setState(() {
      _usarCamara = !_usarCamara;
      if (_usarCamara) {
        _cameraController ??= MobileScannerController();
        _cameraController!.start();
      } else {
        _cameraController?.stop();
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) _qrFocusNode.requestFocus();
        });
      }
    });
  }

  // ── Banner ─────────────────────────────────────────────────────────────────

  Widget _buildBanner() {
    final fecha = DateTime.tryParse(
      _claseSeleccionada?['fecha']?.toString() ?? '',
    );
    if (fecha == null) return const SizedBox.shrink();

    final mins = fecha.difference(_now).inMinutes;
    if (mins <= 0 || mins > 120) return const SizedBox.shrink();

    final String titulo;
    if (mins > 60) {
      final horas = mins ~/ 60;
      final minutosRest = mins % 60;
      final horasStr = horas == 1 ? '1 hora' : '$horas horas';
      titulo = minutosRest == 0
          ? 'La clase empieza en $horasStr'
          : 'La clase empieza en $horasStr y $minutosRest minuto${minutosRest != 1 ? 's' : ''}';
    } else {
      titulo = '¡La clase empieza en $mins minuto${mins != 1 ? 's' : ''}!';
    }

    final totalReservas = _asistentes.length;
    final totalCupos =
        (_claseSeleccionada?['lugares_total'] as num?)?.toInt() ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF0E8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.access_time_rounded,
            color: Color(0xFFE8763A),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$totalReservas alumnos confirmados de $totalCupos cupos',
                  style: const TextStyle(
                    color: Color(0xFF8F877F),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Desktop ────────────────────────────────────────────────────────────────

  Widget _buildDesktopContent() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: class selector + scanner
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Class selector card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16)),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('CLASE ACTIVA', style: TextStyle(color: Color(0xFFB0A8A0), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
                          const SizedBox(height: 6),
                          Text(
                            _claseSeleccionada?['nombre']?.toString() ?? 'Sin clase',
                            style: const TextStyle(color: AppColors.black, fontSize: 18, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    if (_clases.length > 1)
                      TextButton(onPressed: _mostrarSelectorClases, child: const Text('Cambiar', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600))),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _buildBanner(),
              // Scanner
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: AppColors.blackSoft, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_usarCamara ? 'Cámara' : 'Lector USB', style: const TextStyle(color: Color(0xFF9A928B), fontSize: 13, fontWeight: FontWeight.w600)),
                        GestureDetector(
                          onTap: _cambiarModo,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(color: const Color(0xFF2A2A2A), borderRadius: BorderRadius.circular(20)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_usarCamara ? Icons.keyboard_rounded : Icons.camera_alt_rounded, color: AppColors.primary, size: 14),
                                const SizedBox(width: 6),
                                Text(_usarCamara ? 'Usar lector' : 'Usar cámara', style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        height: 260,
                        child: _usarCamara
                            ? _CameraScanner(controller: _cameraController!, procesando: _procesando, onDetect: _validarQR)
                            : _USBScanner(
                                controller: _qrController,
                                focusNode: _qrFocusNode,
                                procesando: _procesando,
                                onSubmit: (v) {
                                  _validarQR(v);
                                  _qrController.clear();
                                  _qrFocusNode.requestFocus();
                                },
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _usarCamara ? 'Apuntá la cámara al QR del usuario' : 'Pasá el lector QR por el código del usuario',
                      style: const TextStyle(color: Color(0xFF8F877F), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        // Right: stats + attendee table
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stats row
              Row(
                children: [
                  Expanded(child: _CountBox(value: _presentes.toString(), label: 'Presentes', color: const Color(0xFFE3F3E5), valueColor: const Color(0xFF43A047))),
                  const SizedBox(width: 8),
                  Expanded(child: _CountBox(value: _pendientes.toString(), label: 'Pendientes', color: const Color(0xFFFFF3DE), valueColor: AppColors.primary)),
                  const SizedBox(width: 8),
                  Expanded(child: _CountBox(value: _ausentes.toString(), label: 'Ausentes', color: const Color(0xFFF1F1F1), valueColor: const Color(0xFF6E6761))),
                ],
              ),
              const SizedBox(height: 14),
              // Attendees table
              const Text('LISTA DE ASISTENTES', style: TextStyle(color: Color(0xFF8F877F), fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1)),
              const SizedBox(height: 10),
              if (_asistentes.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('Sin reservas para esta clase', style: TextStyle(color: Color(0xFF9A928B)))),
                )
              else
                Container(
                  decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: const BoxDecoration(color: Color(0xFFF7F5F2), borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                        child: const Row(
                          children: [
                            Expanded(child: Text('Nombre', style: TextStyle(color: Color(0xFF888888), fontSize: 11, fontWeight: FontWeight.w700))),
                            SizedBox(width: 90, child: Text('Estado', style: TextStyle(color: Color(0xFF888888), fontSize: 11, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
                          ],
                        ),
                      ),
                      ..._asistentes.asMap().entries.map((e) {
                        final a = e.value;
                        final user = a['usuario'] as Map<String, dynamic>?;
                        final nombre = user?['nombre']?.toString() ?? 'Sin nombre';
                        final estado = a['estado']?.toString() ?? 'reservada';
                        final esPresente = estado == 'presente';
                        return Container(
                          decoration: BoxDecoration(
                            border: Border(top: BorderSide(color: Colors.grey.shade100)),
                            borderRadius: e.key == _asistentes.length - 1 ? const BorderRadius.vertical(bottom: Radius.circular(16)) : null,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Container(
                                width: 32, height: 32,
                                decoration: BoxDecoration(color: _avatarColor(nombre), shape: BoxShape.circle),
                                child: Center(child: Text(_initials(nombre), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Text(nombre, style: const TextStyle(color: AppColors.black, fontSize: 14, fontWeight: FontWeight.w500))),
                              SizedBox(
                                width: 90,
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: esPresente ? const Color(0xFFE3F3E5) : const Color(0xFFFFF3DE),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      esPresente ? 'Presente' : 'Pendiente',
                                      style: TextStyle(
                                        color: esPresente ? const Color(0xFF43A047) : AppColors.primary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 768;

    if (isDesktop) {
      return GestureDetector(
        onTap: () { if (!_usarCamara && !_procesando) _qrFocusNode.requestFocus(); },
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : RefreshIndicator(
                  onRefresh: _cargar,
                  color: AppColors.primary,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: _buildDesktopContent(),
                  ),
                ),
        ),
      );
    }

    return GestureDetector(
      // Re-enfocar el campo USB si el usuario toca fuera
      onTap: () {
        if (!_usarCamara && !_procesando) _qrFocusNode.requestFocus();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : SafeArea(
                child: RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                    children: [
                      // Header
                      Row(
                        children: [
                          IconButton(
                            onPressed: () {
                              final router = GoRouter.of(context);
                              if (router.canPop()) {
                                router.pop();
                              } else {
                                context.go('/estudio/dashboard');
                              }
                            },
                            icon: const Icon(Icons.arrow_back_rounded),
                            color: AppColors.black,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Asistencia',
                            style: TextStyle(
                              color: AppColors.black,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Clase activa
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'CLASE ACTIVA',
                                    style: TextStyle(
                                      color: Color(0xFFB0A8A0),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _claseSeleccionada?['nombre']?.toString() ?? 'Sin clase',
                                    style: const TextStyle(
                                      color: AppColors.black,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: _clases.length <= 1 ? null : _mostrarSelectorClases,
                              child: const Text(
                                'Cambiar',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildBanner(),

                      // Scanner
                      Container(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                        decoration: BoxDecoration(
                          color: AppColors.blackSoft,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Column(
                          children: [
                            // Modo toggle
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _usarCamara ? 'Cámara' : 'Lector USB',
                                  style: const TextStyle(
                                    color: Color(0xFF9A928B),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: _cambiarModo,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2A2A2A),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _usarCamara
                                              ? Icons.keyboard_rounded
                                              : Icons.camera_alt_rounded,
                                          color: AppColors.primary,
                                          size: 14,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          _usarCamara ? 'Usar lector' : 'Usar cámara',
                                          style: const TextStyle(
                                            color: AppColors.primary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Scanner area
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                height: 230,
                                child: _usarCamara
                                    ? _CameraScanner(
                                        controller: _cameraController!,
                                        procesando: _procesando,
                                        onDetect: _validarQR,
                                      )
                                    : _USBScanner(
                                        controller: _qrController,
                                        focusNode: _qrFocusNode,
                                        procesando: _procesando,
                                        onSubmit: (v) {
                                          _validarQR(v);
                                          _qrController.clear();
                                          _qrFocusNode.requestFocus();
                                        },
                                      ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _usarCamara
                                  ? 'Apuntá la cámara al QR del usuario'
                                  : 'Pasá el lector QR por el código del usuario',
                              style: const TextStyle(
                                color: Color(0xFF8F877F),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Contadores
                      Row(
                        children: [
                          _CountBox(
                            value: _presentes.toString(),
                            label: 'Presentes',
                            color: const Color(0xFFE3F3E5),
                            valueColor: const Color(0xFF43A047),
                          ),
                          const SizedBox(width: 8),
                          _CountBox(
                            value: _pendientes.toString(),
                            label: 'Pendientes',
                            color: const Color(0xFFFFF3DE),
                            valueColor: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          _CountBox(
                            value: _ausentes.toString(),
                            label: 'Ausentes',
                            color: const Color(0xFFF1F1F1),
                            valueColor: const Color(0xFF6E6761),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Lista
                      const Text(
                        'LISTA DE ASISTENTES',
                        style: TextStyle(
                          color: Color(0xFF8F877F),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_asistentes.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Sin reservas para esta clase',
                              style: TextStyle(color: Color(0xFF9A928B)),
                            ),
                          ),
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            children: _asistentes.map((a) {
                              final user = a['usuario'] as Map<String, dynamic>?;
                              final nombre = user?['nombre']?.toString() ?? 'Sin nombre';
                              final estado = a['estado']?.toString() ?? 'reservada';
                              final esPresente = estado == 'presente';
                              return _AttendeeRow(
                                nombre: nombre,
                                subtitle: esPresente
                                    ? 'Ingreso ${_horaIngreso(a)}'
                                    : 'Pendiente',
                                initials: _initials(nombre),
                                color: _avatarColor(nombre),
                                icon: esPresente
                                    ? Icons.check_circle_rounded
                                    : Icons.access_time_rounded,
                                iconColor: esPresente
                                    ? const Color(0xFF43A047)
                                    : AppColors.primary,
                              );
                            }).toList(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<void> _mostrarSelectorClases() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: _clases.map((clase) {
              return ListTile(
                title: Text(clase['nombre']?.toString() ?? 'Clase'),
                subtitle: Text(
                  DateFormat('EEE d MMM · HH:mm', 'es').format(
                    DateTime.tryParse(clase['fecha']?.toString() ?? '') ?? DateTime.now(),
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _seleccionarClase(clase);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  int get _presentes =>
      _asistentes.where((a) => a['estado'] == 'presente').length;

  int get _pendientes =>
      _asistentes.where((a) => a['estado'] != 'presente' && a['estado'] != 'cancelada').length;

  int get _ausentes =>
      _asistentes.where((a) => a['estado'] == 'cancelada').length;

  String _horaIngreso(Map<String, dynamic> a) {
    final dt = DateTime.tryParse(a['checked_in_at']?.toString() ?? '');
    if (dt == null) return '--:--';
    return DateFormat('HH:mm').format(dt.toLocal());
  }

  String _initials(String name) {
    final parts = name.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '??';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Color _avatarColor(String name) {
    final colors = [
      const Color(0xFFD6E9FF),
      const Color(0xFFFFE1EA),
      const Color(0xFFE5F6E8),
      const Color(0xFFFCEACC),
    ];
    return colors[name.length % colors.length];
  }
}

// ── Camera scanner ─────────────────────────────────────────────────────────

class _CameraScanner extends StatelessWidget {
  final MobileScannerController controller;
  final bool procesando;
  final void Function(String) onDetect;

  const _CameraScanner({
    required this.controller,
    required this.procesando,
    required this.onDetect,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: controller,
          onDetect: (capture) {
            final value = capture.barcodes.firstOrNull?.rawValue;
            if (value != null && !procesando) onDetect(value);
          },
        ),
        // Esquinas del viewfinder
        const Positioned(top: 16, left: 16, child: _ScannerCorner()),
        const Positioned(top: 16, right: 16, child: _ScannerCorner(flipX: true)),
        const Positioned(bottom: 16, left: 16, child: _ScannerCorner(flipY: true)),
        const Positioned(bottom: 16, right: 16, child: _ScannerCorner(flipX: true, flipY: true)),
        // Overlay mientras procesa
        if (procesando)
          Container(
            color: Colors.black54,
            child: const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          ),
      ],
    );
  }
}

// ── USB scanner ───────────────────────────────────────────────────────────

class _USBScanner extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool procesando;
  final void Function(String) onSubmit;

  const _USBScanner({
    required this.controller,
    required this.focusNode,
    required this.procesando,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF2A2A2A),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Campo invisible que captura el input del lector USB
          Opacity(
            opacity: 0,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              onSubmitted: onSubmit,
              decoration: const InputDecoration(border: InputBorder.none),
            ),
          ),
          // UI visual
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  procesando
                      ? Icons.hourglass_top_rounded
                      : Icons.qr_code_scanner_rounded,
                  size: 64,
                  color: procesando ? AppColors.primary : const Color(0xFF595959),
                ),
                const SizedBox(height: 12),
                Text(
                  procesando ? 'Validando...' : 'Esperando QR...',
                  style: TextStyle(
                    color: procesando ? AppColors.primary : const Color(0xFF8F877F),
                    fontSize: 14,
                    fontWeight: procesando ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          // Esquinas del viewfinder
          const Positioned(top: 16, left: 16, child: _ScannerCorner()),
          const Positioned(top: 16, right: 16, child: _ScannerCorner(flipX: true)),
          const Positioned(bottom: 16, left: 16, child: _ScannerCorner(flipY: true)),
          const Positioned(bottom: 16, right: 16, child: _ScannerCorner(flipX: true, flipY: true)),
        ],
      ),
    );
  }
}

// ── Result popup ──────────────────────────────────────────────────────────

class _ResultPopup extends StatelessWidget {
  final bool exito;
  final String titulo;
  final String subtitulo;

  const _ResultPopup({
    required this.exito,
    required this.titulo,
    required this.subtitulo,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: exito ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              exito ? Icons.check_circle_rounded : Icons.cancel_rounded,
              size: 72,
              color: exito ? const Color(0xFF43A047) : AppColors.error,
            ),
            const SizedBox(height: 16),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.black,
              ),
            ),
            if (subtitulo.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtitulo,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6E6761),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────

class _ScannerCorner extends StatelessWidget {
  final bool flipX;
  final bool flipY;

  const _ScannerCorner({this.flipX = false, this.flipY = false});

  @override
  Widget build(BuildContext context) {
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..scale(flipX ? -1.0 : 1.0, flipY ? -1.0 : 1.0),
      child: Container(
        width: 28,
        height: 28,
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.primary, width: 4),
            left: BorderSide(color: AppColors.primary, width: 4),
          ),
        ),
      ),
    );
  }
}

class _CountBox extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final Color valueColor;

  const _CountBox({
    required this.value,
    required this.label,
    required this.color,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Color(0xFF6E6761), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttendeeRow extends StatelessWidget {
  final String nombre;
  final String subtitle;
  final String initials;
  final Color color;
  final IconData icon;
  final Color iconColor;

  const _AttendeeRow({
    required this.nombre,
    required this.subtitle,
    required this.initials,
    required this.color,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color,
            child: Text(
              initials,
              style: const TextStyle(
                color: Color(0xFF4473B9),
                fontWeight: FontWeight.w700,
                fontSize: 13,
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
                  style: const TextStyle(
                    color: AppColors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: subtitle == 'Pendiente'
                        ? AppColors.primary
                        : const Color(0xFF9A928B),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Icon(icon, color: iconColor),
        ],
      ),
    );
  }
}
