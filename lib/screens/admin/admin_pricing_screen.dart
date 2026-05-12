import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';

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
  static const _diasShort = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

  final _client = Supabase.instance.client;

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _estudioCategoria;

  // Estado: por celda (dia, hora) → tipo. Si no existe, no marcada.
  // dia 1..7, hora 'HH:mm' (slot de 30 min: 06:00, 06:30, ..., 22:30)
  final Map<String, String> _celdas = {}; // key 'd-HH:mm' -> 'pico'|'valle'

  // Categorias con min/max
  final Map<String, _RangeCtrls> _rangos = {};
  // Categorias disponibles (todas las del estudio + estandar)
  final Set<String> _categorias = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final r in _rangos.values) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final row = await _client
          .from('estudios')
          .select(
              'id, nombre, categoria, horarios_config, precio_min, precio_max')
          .eq('id', widget.estudioId)
          .maybeSingle();
      if (row == null) {
        setState(() {
          _loading = false;
          _error = 'No se encontró el estudio.';
        });
        return;
      }
      _estudioCategoria = row['categoria']?.toString();

      // Leer celdas pico/valle
      final config = row['horarios_config'];
      _celdas.clear();
      _marcarRangos(config, 'pico');
      _marcarRangos(config, 'valle');

      // Cargar categorias y rangos
      final precioMin = _readIntMap(row['precio_min']);
      final precioMax = _readIntMap(row['precio_max']);
      _categorias
        ..clear()
        ..addAll(precioMin.keys)
        ..addAll(precioMax.keys);
      if (_estudioCategoria != null && _estudioCategoria!.isNotEmpty) {
        _categorias.add(_estudioCategoria!.toLowerCase());
      }
      // Sugerencias por defecto si todavia no tiene nada
      if (_categorias.isEmpty) {
        _categorias.addAll(['pilates', 'yoga', 'gym']);
      }
      _rangos.clear();
      for (final c in _categorias) {
        _rangos[c] = _RangeCtrls(
          min: TextEditingController(text: precioMin[c]?.toString() ?? ''),
          max: TextEditingController(text: precioMax[c]?.toString() ?? ''),
        );
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

  void _marcarRangos(dynamic config, String tipo) {
    if (config is! Map) return;
    final lista = config[tipo];
    if (lista is! List) return;
    for (final r in lista) {
      if (r is! Map) continue;
      final dia = (r['dia'] is num)
          ? (r['dia'] as num).toInt()
          : int.tryParse(r['dia']?.toString() ?? '');
      if (dia == null || dia < 1 || dia > 7) continue;
      final inicio = r['hora_inicio']?.toString() ?? '';
      final fin = r['hora_fin']?.toString() ?? '';
      // Marcar todas las celdas de 30min que caigan dentro de [inicio, fin)
      for (final hora in _horasDelDia()) {
        if (inicio.compareTo(hora) <= 0 && hora.compareTo(fin) < 0) {
          _celdas['$dia-$hora'] = tipo;
        }
      }
    }
  }

  Map<String, int> _readIntMap(dynamic raw) {
    if (raw is! Map) return const {};
    final result = <String, int>{};
    raw.forEach((k, v) {
      final intV = (v is num) ? v.toInt() : int.tryParse(v?.toString() ?? '');
      if (intV != null) result[k.toString().toLowerCase()] = intV;
    });
    return result;
  }

  List<String> _horasDelDia() {
    final result = <String>[];
    for (var h = 6; h <= 22; h++) {
      result.add('${h.toString().padLeft(2, '0')}:00');
      result.add('${h.toString().padLeft(2, '0')}:30');
    }
    // Hasta 23:00 inclusive
    result.add('23:00');
    return result;
  }

  String _siguienteSlot(String hora) {
    final partes = hora.split(':');
    final h = int.parse(partes[0]);
    final m = int.parse(partes[1]);
    final total = h * 60 + m + 30;
    return '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _onTapCelda(int dia, String hora) async {
    if (widget.readOnly) return;
    final key = '$dia-$hora';
    final actual = _celdas[key];
    if (actual != null) {
      setState(() => _celdas.remove(key));
      return;
    }
    final tipo = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_diasShort[dia - 1]} a las $hora',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.black,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, 'pico'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _picoColor,
                        foregroundColor: AppColors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('⚡ Pico'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, 'valle'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _valleColor,
                        foregroundColor: AppColors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('🏷️ Valle'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (tipo == null) return;
    setState(() => _celdas[key] = tipo);
  }

  Future<void> _guardar() async {
    if (widget.readOnly) return;
    setState(() => _saving = true);
    try {
      // Construir precio_min y precio_max desde controllers
      final precioMin = <String, int>{};
      final precioMax = <String, int>{};
      for (final entry in _rangos.entries) {
        final min = int.tryParse(entry.value.min.text.trim());
        final max = int.tryParse(entry.value.max.text.trim());
        if (min != null) precioMin[entry.key] = min;
        if (max != null) precioMax[entry.key] = max;
      }

      // Construir horarios_config desde el grid
      final pico = <Map<String, dynamic>>[];
      final valle = <Map<String, dynamic>>[];
      _celdas.forEach((key, tipo) {
        final partes = key.split('-');
        final dia = int.parse(partes[0]);
        final hora = partes[1];
        final entry = {
          'dia': dia,
          'hora_inicio': hora,
          'hora_fin': _siguienteSlot(hora),
        };
        (tipo == 'pico' ? pico : valle).add(entry);
      });

      await _client.from('estudios').update({
        'horarios_config': {'pico': pico, 'valle': valle},
        'precio_min': precioMin,
        'precio_max': precioMax,
      }).eq('id', widget.estudioId);

      // Re-aplicar pricing a las clases futuras del estudio
      try {
        await _client.rpc(
          'aplicar_pricing_a_clases_futuras',
          params: {'p_estudio_id': widget.estudioId},
        );
      } catch (_) {}

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configuración guardada. Precios aplicados a clases futuras.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _agregarCategoria() async {
    final ctrl = TextEditingController();
    final nombre = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva categoría'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'ej. ceramica, danza'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim().toLowerCase()),
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (nombre == null || nombre.isEmpty) return;
    if (_rangos.containsKey(nombre)) return;
    setState(() {
      _categorias.add(nombre);
      _rangos[nombre] = _RangeCtrls(
        min: TextEditingController(),
        max: TextEditingController(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.readOnly
            ? 'Precios del estudio'
            : 'Precios — ${widget.estudioNombre ?? 'estudio'}'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
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
                      _buildRangosSection(),
                      const SizedBox(height: 24),
                      _buildGridSection(),
                      const SizedBox(height: 28),
                      if (!widget.readOnly)
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
                            child: Text(_saving
                                ? 'Guardando…'
                                : 'Guardar configuración'),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildRangosSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Rango de precios por categoría',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.black,
                ),
              ),
            ),
            if (!widget.readOnly)
              TextButton.icon(
                onPressed: _agregarCategoria,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Categoría'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Mínimo = precio en horario valle. Máximo = precio en horario pico. '
          'En horario normal se cobra el promedio.',
          style: TextStyle(color: AppColors.grey, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 16),
        ..._categorias.toList().map((cat) {
          final rng = _rangos[cat];
          if (rng == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      _capitalize(cat),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.black,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: rng.min,
                      enabled: !widget.readOnly,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Mín',
                        suffixText: 'cr',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: rng.max,
                      enabled: !widget.readOnly,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Máx',
                        suffixText: 'cr',
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildGridSection() {
    final horas = _horasDelDia();
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
          'Tocá una celda para marcarla como pico (naranja) o valle (verde). '
          'Tocá una marcada para desmarcarla.',
          style: TextStyle(color: AppColors.grey, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Row(
                children: [
                  const SizedBox(width: 48),
                  for (final d in _diasShort)
                    Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.grey,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              ...horas.map((hora) => _buildRow(hora)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: const [
            _LegendDot(color: _picoColor, label: '⚡ Pico'),
            SizedBox(width: 14),
            _LegendDot(color: _valleColor, label: '🏷️ Valle'),
            SizedBox(width: 14),
            _LegendDot(color: Color(0xFFEDE7E1), label: 'Sin marcar'),
          ],
        ),
      ],
    );
  }

  Widget _buildRow(String hora) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              hora,
              style: const TextStyle(fontSize: 11, color: AppColors.grey),
            ),
          ),
          for (var dia = 1; dia <= 7; dia++)
            Expanded(child: _buildCelda(dia, hora)),
        ],
      ),
    );
  }

  Widget _buildCelda(int dia, String hora) {
    final tipo = _celdas['$dia-$hora'];
    Color color;
    if (tipo == 'pico') {
      color = _picoColor;
    } else if (tipo == 'valle') {
      color = _valleColor;
    } else {
      color = const Color(0xFFEDE7E1);
    }
    return GestureDetector(
      onTap: () => _onTapCelda(dia, hora),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1),
        height: 18,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _RangeCtrls {
  final TextEditingController min;
  final TextEditingController max;
  _RangeCtrls({required this.min, required this.max});
  void dispose() {
    min.dispose();
    max.dispose();
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
