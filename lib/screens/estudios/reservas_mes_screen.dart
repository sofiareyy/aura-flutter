// Las reservas del estudio, mes por mes (4/10/2026).
//
// Por qué existe: el panel sólo miraba de HOY en adelante. La pantalla de
// asistencia pide las clases de hoy y el dashboard muestra números, no una
// lista. Una reserva de ayer —alguien reservó en Citra el 3/10— no se podía
// ver en ninguna parte, y el estudio no tenía cómo revisar quién vino.
//
// Muestra: cuándo fue la clase, cuál, quién reservó, cuántos créditos y si
// se le marcó el presente.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/aura_tokens.dart';
import '../../services/estudio_admin_service.dart';
import '../../widgets/ancho_maximo.dart';

class ReservasMesScreen extends StatefulWidget {
  const ReservasMesScreen({super.key});

  @override
  State<ReservasMesScreen> createState() => _ReservasMesScreenState();
}

class _ReservasMesScreenState extends State<ReservasMesScreen> {
  final _service = EstudioAdminService();

  /// Primer día del mes que se está mirando. Arranca en el mes en curso.
  late DateTime _mes;
  List<Map<String, dynamic>> _reservas = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final ahora = DateTime.now();
    _mes = DateTime(ahora.year, ahora.month);
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    try {
      final filas = await _service.getReservasEnRango(
        desde: _mes,
        hasta: DateTime(_mes.year, _mes.month + 1),
      );
      if (!mounted) return;
      setState(() {
        _reservas = filas;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _reservas = const [];
        _loading = false;
      });
    }
  }

  void _moverMes(int delta) {
    setState(() => _mes = DateTime(_mes.year, _mes.month + delta));
    _cargar();
  }

  bool get _esMesActual {
    final ahora = DateTime.now();
    return _mes.year == ahora.year && _mes.month == ahora.month;
  }

  int get _presentes =>
      _reservas.where((r) => r['checked_in_at'] != null).length;

  int get _creditos => _reservas.fold<int>(
    0,
    (total, r) => total + ((r['creditos_usados'] as num?)?.toInt() ?? 0),
  );

  @override
  Widget build(BuildContext context) {
    final titulo = DateFormat("MMMM 'de' y", 'es').format(_mes);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Reservas del mes')),
      body: AnchoMaximo(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _cargar,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => _moverMes(-1),
                    icon: const Icon(Icons.chevron_left_rounded),
                    tooltip: 'Mes anterior',
                  ),
                  Expanded(
                    child: Text(
                      titulo[0].toUpperCase() + titulo.substring(1),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.black,
                        fontSize: AuraTipo.titulo,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    // No se puede ir al futuro: no hay reservas que mirar.
                    onPressed: _esMesActual ? null : () => _moverMes(1),
                    icon: const Icon(Icons.chevron_right_rounded),
                    tooltip: 'Mes siguiente',
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (!_loading && _reservas.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(AuraRadio.tarjeta),
                    border: Border.all(color: AppColors.warmBorder),
                  ),
                  child: Row(
                    children: [
                      _Dato(valor: '${_reservas.length}', etiqueta: 'reservas'),
                      _Dato(valor: '$_presentes', etiqueta: 'presentes'),
                      _Dato(valor: '$_creditos', etiqueta: 'créditos'),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                )
              else if (_reservas.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 50),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.event_busy_outlined,
                        size: 42,
                        color: AppColors.grey,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No hubo reservas en ${titulo.split(' ').first}.',
                        style: const TextStyle(
                          color: AppColors.grey,
                          fontSize: AuraTipo.cuerpo,
                        ),
                      ),
                    ],
                  ),
                )
              else
                for (final r in _reservas) _FilaReserva(reserva: r),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  final String valor;
  final String etiqueta;

  const _Dato({required this.valor, required this.etiqueta});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            valor,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            etiqueta,
            style: const TextStyle(
              color: AppColors.grey,
              fontSize: AuraTipo.secundario,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilaReserva extends StatelessWidget {
  final Map<String, dynamic> reserva;

  const _FilaReserva({required this.reserva});

  @override
  Widget build(BuildContext context) {
    final clase = reserva['clases'] as Map<String, dynamic>?;
    final alumna = reserva['usuarios'] as Map<String, dynamic>?;
    final fecha = DateTime.tryParse(clase?['fecha']?.toString() ?? '');
    final presente = reserva['checked_in_at'] != null;
    final estado = reserva['estado']?.toString() ?? '';
    final cancelada = estado == 'cancelada';
    final nombre = (alumna?['nombre']?.toString().trim() ?? '');
    final quien = nombre.isNotEmpty
        ? nombre
        : (alumna?['email']?.toString() ?? 'Alumna');
    final creditos = (reserva['creditos_usados'] as num?)?.toInt() ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AuraRadio.tarjeta),
        border: Border.all(color: AppColors.warmBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fecha == null
                      ? 'Sin fecha'
                      : DateFormat("EEE d 'de' MMM · HH:mm", 'es').format(fecha),
                  style: const TextStyle(
                    color: AppColors.black,
                    fontSize: AuraTipo.cuerpo,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  clase?['nombre']?.toString() ?? 'Clase',
                  style: const TextStyle(
                    color: AppColors.textoSecundario,
                    fontSize: AuraTipo.secundario,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.person_outline_rounded,
                      size: 15,
                      color: AppColors.grey,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        quien,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.black,
                          fontSize: AuraTipo.secundario,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (creditos > 0) ...[
                      const SizedBox(width: 10),
                      Text(
                        '$creditos cr',
                        style: const TextStyle(
                          color: AppColors.grey,
                          fontSize: AuraTipo.secundario,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _Marca(presente: presente, cancelada: cancelada),
        ],
      ),
    );
  }
}

/// La marca de la derecha. Tres estados y no dos: "sin presente" NO es lo
/// mismo que "no vino" —puede ser que el estudio no lo haya marcado— así que
/// el texto no acusa a nadie.
class _Marca extends StatelessWidget {
  final bool presente;
  final bool cancelada;

  const _Marca({required this.presente, required this.cancelada});

  @override
  Widget build(BuildContext context) {
    final (texto, fondo, color) = cancelada
        ? ('Cancelada', const Color(0xFFF3EEE8), AppColors.grey)
        : presente
        ? ('Presente', const Color(0xFFE8F3E9), Color(0xFF2E6B33))
        : ('Sin marcar', AppColors.primaryLight, AppColors.primaryTexto);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(AuraRadio.pastilla),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: color,
          fontSize: AuraTipo.etiqueta,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
