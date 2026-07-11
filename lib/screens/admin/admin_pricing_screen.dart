import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../services/pricing_service.dart';
import '../../utils/pricing.dart';

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

  bool _loading = true;
  bool _saving = false;
  String? _error;

  String _tipoEstudio = 'fitness'; // 'fitness' | 'experiencia'
  int _valorCredito = 1000;

  // fitness: un solo rango por estudio
  final _minCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();
  // experiencia: precio fijo (legacy, ya no se muestra)
  final _fijoCtrl = TextEditingController();
  // experiencia: comisión de workshops (%). El precio lo pone el estudio en
  // cada workshop, no acá.
  final _comisionWorkshopCtrl = TextEditingController();

  // horarios: clave "dia|rango" -> 'pico' | 'valle'
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
      final row = await _client
          .from('estudios')
          .select(
              'id, nombre, tipo_estudio, precio_config, horarios_config, comision_workshop')
          .eq('id', widget.estudioId)
          .maybeSingle();
      _valorCredito = await _pricingService.getValorCreditoArs();

      if (row == null) {
        setState(() {
          _loading = false;
          _error = 'No se encontró el estudio.';
        });
        return;
      }

      _tipoEstudio =
          (row['tipo_estudio']?.toString() ?? 'fitness').toLowerCase();

      // precio_config = {"min": 10, "max": 18, "pico_multiplier": 1.0}
      final config = row['precio_config'];
      int? min;
      int? max;
      if (config is Map) {
        min = _asInt(config['min']);
        max = _asInt(config['max']);
      }
      _minCtrl.text = min?.toString() ?? '';
      _maxCtrl.text = max?.toString() ?? '';
      // para experiencia el precio fijo se guarda en min
      _fijoCtrl.text = min?.toString() ?? '';
      _comisionWorkshopCtrl.text =
          (_asInt(row['comision_workshop']) ?? 15).toString();

      // horarios_config = {"pico": [{"dia":1,"rango":"tarde_noche"}], "valle": [...]}
      _clasificacion.clear();
      final horarios = row['horarios_config'];
      if (horarios is Map) {
        _cargarClasificacion(horarios['pico'], 'pico');
        _cargarClasificacion(horarios['valle'], 'valle');
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

  void _cargarClasificacion(dynamic arr, String tipo) {
    if (arr is! List) return;
    for (final e in arr) {
      if (e is! Map) continue;
      final dia = _asInt(e['dia']);
      final rango = e['rango']?.toString();
      if (dia != null && rango != null && rango.isNotEmpty) {
        _clasificacion['$dia|$rango'] = tipo;
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
        await _client.from('estudios').update({
          'tipo_estudio': 'experiencia',
          'comision_workshop': comision,
        }).eq('id', widget.estudioId);
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

    final Map<String, dynamic> precioConfig;
    Map<String, dynamic> horariosConfig = {'pico': [], 'valle': []};

    {
      final min = int.tryParse(_minCtrl.text.trim());
      final max = int.tryParse(_maxCtrl.text.trim());
      if (min == null || max == null) {
        _snack('Completá el precio mínimo y máximo.');
        return;
      }
      if (max < min) {
        _snack('El precio máximo no puede ser menor al mínimo.');
        return;
      }
      precioConfig = {'min': min, 'max': max, 'pico_multiplier': 1.0};

      final pico = <Map<String, dynamic>>[];
      final valle = <Map<String, dynamic>>[];
      _clasificacion.forEach((key, tipo) {
        final parts = key.split('|');
        if (parts.length != 2) return;
        final dia = int.tryParse(parts[0]);
        if (dia == null) return;
        final entry = {'dia': dia, 'rango': parts[1]};
        (tipo == 'pico' ? pico : valle).add(entry);
      });
      horariosConfig = {'pico': pico, 'valle': valle};
    }

    setState(() => _saving = true);
    try {
      await _client.from('estudios').update({
        'tipo_estudio': _tipoEstudio,
        'precio_config': precioConfig,
        'horarios_config': horariosConfig,
      }).eq('id', widget.estudioId);

      try {
        await _client.rpc(
          'aplicar_pricing_a_clases_futuras',
          params: {'p_estudio_id': widget.estudioId},
        );
      } catch (_) {}

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Configuración guardada. Precios aplicados a clases futuras.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      _snack('No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
        title: Text(widget.estudioNombre != null
            ? 'Precios — ${widget.estudioNombre}'
            : 'Precios del estudio'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
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
                        _buildRangoFitness(),
                        const SizedBox(height: 24),
                        _buildHorarios(),
                      ] else
                        _buildPrecioExperiencia(),
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
                              _saving ? 'Guardando…' : 'Guardar configuración'),
                        ),
                      ),
                    ],
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

  Widget _buildRangoFitness() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Rango de precio del estudio',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.black,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Tu rango negociado en créditos. En horario pico la clase cuesta el '
          'máximo; en normal, el mínimo; en valle, el mínimo con 10% de '
          'descuento.',
          style: TextStyle(color: AppColors.grey, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _minCtrl,
                enabled: !widget.readOnly,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Precio mínimo',
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
                  labelText: 'Precio máximo',
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
    final max = int.tryParse(_maxCtrl.text.trim());
    final String texto;
    if (min == null && max == null) {
      texto = 'Completá el rango para ver cuánto recibe el estudio por clase.';
    } else {
      final lo = min ?? max!;
      final hi = max ?? min!;
      final recibeLo = _pricingService.montoEstudioPorClase(_valorCredito, lo);
      final recibeHi = _pricingService.montoEstudioPorClase(_valorCredito, hi);
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
          const Icon(Icons.payments_outlined, color: AppColors.primary, size: 18),
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
          'Tocá un bloque para clasificarlo. 1 toque = ⚡ pico, 2 toques = '
          '🌙 valle, 3 toques = normal. Los bloques sin marcar son normales.',
          style: TextStyle(color: AppColors.grey, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 14),
        for (int dia = 1; dia <= 7; dia++) _buildDiaRow(dia),
      ],
    );
  }

  Widget _buildDiaRow(int dia) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _diasSemana[dia],
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.black,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kRangosHorarios.map((r) {
              final key = '$dia|${r.key}';
              final estado = _clasificacion[key]; // null | 'pico' | 'valle'
              final Color bg;
              final Color fg;
              final String prefix;
              if (estado == 'pico') {
                bg = _picoColor;
                fg = AppColors.white;
                prefix = '⚡ ';
              } else if (estado == 'valle') {
                bg = _valleColor;
                fg = AppColors.white;
                prefix = '🌙 ';
              } else {
                bg = AppColors.white;
                fg = AppColors.black;
                prefix = '';
              }
              return GestureDetector(
                onTap: widget.readOnly ? null : () => _ciclarEstado(key),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: estado == null ? const Color(0xFFEDE7E1) : bg,
                    ),
                  ),
                  child: Text(
                    '$prefix${r.label}',
                    style: TextStyle(
                      color: fg,
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

  void _ciclarEstado(String key) {
    setState(() {
      final actual = _clasificacion[key];
      if (actual == null) {
        _clasificacion[key] = 'pico';
      } else if (actual == 'pico') {
        _clasificacion[key] = 'valle';
      } else {
        _clasificacion.remove(key);
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
