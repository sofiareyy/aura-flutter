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

  final _client = Supabase.instance.client;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  String _tipoEstudio = 'fitness'; // 'fitness' | 'experiencia'
  final Set<String> _horasPico = {};
  final Map<String, _FitnessCtrls> _fitnessCtrls = {};
  final Map<String, TextEditingController> _experienciaCtrls = {};
  final Set<String> _categorias = {};

  static const _horasDisponibles = [
    '06:00', '07:00', '08:00', '09:00', '10:00', '11:00',
    '12:00', '13:00', '14:00', '15:00', '16:00', '17:00',
    '18:00', '19:00', '20:00', '21:00', '22:00', '23:00',
  ];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final c in _fitnessCtrls.values) {
      c.dispose();
    }
    for (final c in _experienciaCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final row = await _client
          .from('estudios')
          .select(
              'id, nombre, categoria, tipo_estudio, horarios_pico, precio_config')
          .eq('id', widget.estudioId)
          .maybeSingle();
      if (row == null) {
        setState(() {
          _loading = false;
          _error = 'No se encontró el estudio.';
        });
        return;
      }

      _tipoEstudio = (row['tipo_estudio']?.toString() ?? 'fitness').toLowerCase();

      // horas pico
      final hp = row['horarios_pico'];
      _horasPico.clear();
      if (hp is List) {
        for (final h in hp) {
          _horasPico.add(h.toString());
        }
      }

      // categorias
      _categorias.clear();
      final estudioCat = row['categoria']?.toString().toLowerCase() ?? '';
      if (estudioCat.isNotEmpty) _categorias.add(estudioCat);

      final config = row['precio_config'];
      if (config is Map) {
        for (final k in config.keys) {
          _categorias.add(k.toString().toLowerCase());
        }
      }
      if (_categorias.isEmpty) {
        _categorias.addAll(['pilates', 'yoga']);
      }

      _fitnessCtrls.clear();
      _experienciaCtrls.clear();
      for (final cat in _categorias) {
        if (_tipoEstudio == 'experiencia') {
          final val = (config is Map) ? config[cat] : null;
          _experienciaCtrls[cat] = TextEditingController(
            text: (val is num) ? val.toInt().toString() : (val?.toString() ?? ''),
          );
        } else {
          final sub = (config is Map) ? config[cat] : null;
          int? normal;
          int? pico;
          if (sub is Map) {
            final n = sub['normal'];
            final p = sub['pico'];
            if (n is num) normal = n.toInt();
            if (p is num) pico = p.toInt();
          }
          _fitnessCtrls[cat] = _FitnessCtrls(
            normal: TextEditingController(text: normal?.toString() ?? ''),
            pico: TextEditingController(text: pico?.toString() ?? ''),
          );
        }
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

  Future<void> _guardar() async {
    if (widget.readOnly) return;
    setState(() => _saving = true);
    try {
      final Map<String, dynamic> precioConfig = {};
      if (_tipoEstudio == 'experiencia') {
        for (final entry in _experienciaCtrls.entries) {
          final v = int.tryParse(entry.value.text.trim());
          if (v != null) precioConfig[entry.key] = v;
        }
      } else {
        for (final entry in _fitnessCtrls.entries) {
          final normal = int.tryParse(entry.value.normal.text.trim());
          final pico = int.tryParse(entry.value.pico.text.trim());
          if (normal != null || pico != null) {
            precioConfig[entry.key] = {
              if (normal != null) 'normal': normal,
              if (pico != null) 'pico': pico,
            };
          }
        }
      }

      await _client.from('estudios').update({
        'tipo_estudio': _tipoEstudio,
        'horarios_pico':
            _tipoEstudio == 'fitness' ? _horasPico.toList() : <String>[],
        'precio_config': precioConfig,
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
          decoration: const InputDecoration(hintText: 'ej. ceramica, taller'),
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
    if (_categorias.contains(nombre)) return;
    setState(() {
      _categorias.add(nombre);
      if (_tipoEstudio == 'experiencia') {
        _experienciaCtrls[nombre] = TextEditingController();
      } else {
        _fitnessCtrls[nombre] = _FitnessCtrls(
          normal: TextEditingController(),
          pico: TextEditingController(),
        );
      }
    });
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
                      _buildToggleTipo(),
                      const SizedBox(height: 20),
                      if (_tipoEstudio == 'fitness') ...[
                        _buildHorariosPico(),
                        const SizedBox(height: 20),
                        _buildPreciosFitness(),
                      ] else ...[
                        _buildPreciosExperiencia(),
                      ],
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
                          child: Text(_saving ? 'Guardando…' : 'Guardar configuración'),
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
          onTap: widget.readOnly ? null : () => setState(() => _tipoEstudio = value),
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
              ? 'Precios cambian según día/hora (pico vs normal)'
              : 'Precios fijos por categoría',
          style: const TextStyle(color: AppColors.grey, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildHorariosPico() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Horarios pico',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.black,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Tocá las horas que querés marcar como pico. Las no marcadas son horario normal.',
          style: TextStyle(color: AppColors.grey, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _horasDisponibles.map((h) {
            final selected = _horasPico.contains(h);
            return GestureDetector(
              onTap: widget.readOnly
                  ? null
                  : () => setState(() {
                        if (selected) {
                          _horasPico.remove(h);
                        } else {
                          _horasPico.add(h);
                        }
                      }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? _picoColor : AppColors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected ? _picoColor : const Color(0xFFEDE7E1),
                  ),
                ),
                child: Text(
                  selected ? '⚡ $h' : h,
                  style: TextStyle(
                    color: selected ? AppColors.white : AppColors.black,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildPreciosFitness() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Precios por categoría',
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
        const SizedBox(height: 12),
        ..._categorias.toList().map((cat) {
          final c = _fitnessCtrls[cat];
          if (c == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _capitalize(cat),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.black,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: c.normal,
                          enabled: !widget.readOnly,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Normal',
                            suffixText: 'cr',
                            isDense: true,
                            prefixIcon: Icon(
                              Icons.label_outline,
                              color: _valleColor,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: c.pico,
                          enabled: !widget.readOnly,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Pico',
                            suffixText: 'cr',
                            isDense: true,
                            prefixIcon: Icon(
                              Icons.bolt,
                              color: _picoColor,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildPreciosExperiencia() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Precio por categoría',
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
        const SizedBox(height: 12),
        ..._categorias.toList().map((cat) {
          final c = _experienciaCtrls[cat];
          if (c == null) return const SizedBox.shrink();
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
                        fontWeight: FontWeight.w700,
                        color: AppColors.black,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: c,
                      enabled: !widget.readOnly,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Precio fijo',
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

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _FitnessCtrls {
  final TextEditingController normal;
  final TextEditingController pico;
  _FitnessCtrls({required this.normal, required this.pico});
  void dispose() {
    normal.dispose();
    pico.dispose();
  }
}
