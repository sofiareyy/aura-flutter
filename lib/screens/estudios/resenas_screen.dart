import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../services/reviews_service.dart';
import '../../utils/resenas.dart';

/// Todas las reseñas de un estudio. UNA pantalla para las DOS puntas:
///
///  · la alumna llega tocando el promedio (perfil del estudio / detalle de
///    clase) — las reseñas ayudan a decidir la reserva;
///  · el estudio llega desde la tarjeta de su Dashboard.
///
/// La lista es la misma (la policy de `study_reviews` es pública porque las
/// reseñas se muestran en el perfil): lo único que cambia es el título.
class ResenasScreen extends StatefulWidget {
  final int estudioId;

  /// Nombre para el título. Si es null se muestra "Reseñas" a secas.
  final String? estudioNombre;

  /// true = lo abre el estudio dueño ("Tus reseñas").
  final bool esDueno;

  const ResenasScreen({
    super.key,
    required this.estudioId,
    this.estudioNombre,
    this.esDueno = false,
  });

  @override
  State<ResenasScreen> createState() => _ResenasScreenState();
}

class _ResenasScreenState extends State<ResenasScreen> {
  static const _pageSize = 20;

  final _service = ReviewsService();

  Map<int, int> _desglose = const {};
  List<Map<String, dynamic>> _resenas = [];
  /// {usuario_id: nombre a mostrar}. El formato depende de quién mira: el
  /// estudio ve "Juana Sosa", la alumna "Juana S.".
  Map<String, String> _nombres = {};
  int? _filtro; // null = todas
  bool _loading = true;
  bool _loadingMore = false;
  bool _hayMas = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final desglose = await _service.getRatingBreakdown(widget.estudioId);
      final primera = await _service.getReviewsPage(
        widget.estudioId,
        rating: _filtro,
        limit: _pageSize,
      );
      final nombres = await _service.getNombresAutoras(
        primera
            .map((r) => r['usuario_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList(),
        esDueno: widget.esDueno,
      );
      if (!mounted) return;
      setState(() {
        _desglose = desglose;
        _resenas = primera;
        _nombres = nombres;
        _hayMas = primera.length == _pageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos cargar las reseñas. Probá de nuevo.';
        _loading = false;
      });
    }
  }

  Future<void> _cargarMas() async {
    if (_loadingMore || !_hayMas) return;
    setState(() => _loadingMore = true);
    try {
      final mas = await _service.getReviewsPage(
        widget.estudioId,
        rating: _filtro,
        offset: _resenas.length,
        limit: _pageSize,
      );
      final nuevos = await _service.getNombresAutoras(
        mas
            .map((r) => r['usuario_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty && !_nombres.containsKey(id))
            .toSet()
            .toList(),
        esDueno: widget.esDueno,
      );
      if (!mounted) return;
      setState(() {
        _resenas = [..._resenas, ...mas];
        _nombres = {..._nombres, ...nuevos};
        _hayMas = mas.length == _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _aplicarFiltro(int? rating) async {
    setState(() => _filtro = rating);
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final total = Resenas.totalDe(_desglose);
    final promedio = Resenas.promedioDe(_desglose);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.esDueno
            ? 'Tus reseñas'
            : (widget.estudioNombre?.isNotEmpty == true
                ? 'Reseñas de ${widget.estudioNombre}'
                : 'Reseñas')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.grey)),
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                    children: [
                      _Resumen(
                          promedio: promedio, total: total, desglose: _desglose),
                      const SizedBox(height: 18),
                      if (total > 0)
                        _Filtros(
                          desglose: _desglose,
                          seleccionado: _filtro,
                          onSeleccionar: _aplicarFiltro,
                        ),
                      const SizedBox(height: 16),
                      if (_resenas.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Text(
                              _filtro == null
                                  ? 'Todavía no hay reseñas.'
                                  : 'No hay reseñas de $_filtro estrella${_filtro == 1 ? '' : 's'}.',
                              style: const TextStyle(color: AppColors.grey),
                            ),
                          ),
                        )
                      else ...[
                        ..._resenas.map((r) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: ResenaCard(
                                resena: r,
                                nombre:
                                    _nombres[r['usuario_id']?.toString()],
                              ),
                            )),
                        if (_hayMas)
                          Center(
                            child: _loadingMore
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.primary),
                                    ),
                                  )
                                : TextButton(
                                    onPressed: _cargarMas,
                                    child: const Text('Cargar más'),
                                  ),
                          ),
                      ],
                    ],
                  ),
                ),
    );
  }
}

/// Promedio grande + desglose por estrellas. El desglose es el resumen más
/// útil: de un vistazo se ve si hay quejas, no sólo cuánto da el promedio.
class _Resumen extends StatelessWidget {
  final double? promedio;
  final int total;
  final Map<int, int> desglose;

  const _Resumen(
      {required this.promedio, required this.total, required this.desglose});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Text(
            Resenas.formatearPromedio(promedio),
            style: const TextStyle(
              color: AppColors.black,
              fontSize: 34,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          _Estrellas(rating: (promedio ?? 0).round(), size: 20),
          const SizedBox(height: 6),
          Text(
            Resenas.etiquetaTotal(total),
            style: const TextStyle(color: AppColors.grey, fontSize: 13),
          ),
          if (total > 0) ...[
            const SizedBox(height: 16),
            for (var estrella = 5; estrella >= 1; estrella--)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 26,
                      child: Text('$estrella★',
                          style: const TextStyle(
                              color: AppColors.grey, fontSize: 12)),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: (desglose[estrella] ?? 0) / total,
                          minHeight: 7,
                          backgroundColor: const Color(0xFFF0EDE9),
                          valueColor: const AlwaysStoppedAnimation(
                              AppColors.warning),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 26,
                      child: Text('${desglose[estrella] ?? 0}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              color: AppColors.grey, fontSize: 12)),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Filtros por estrellas. Los que están en 0 se ven deshabilitados, NO se
/// ocultan: que no haya reseñas de 1★ es información.
class _Filtros extends StatelessWidget {
  final Map<int, int> desglose;
  final int? seleccionado;
  final ValueChanged<int?> onSeleccionar;

  const _Filtros({
    required this.desglose,
    required this.seleccionado,
    required this.onSeleccionar,
  });

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, int? valor, {bool habilitado = true}) {
      final activo = seleccionado == valor;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: habilitado ? () => onSeleccionar(valor) : null,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: activo ? AppColors.black : AppColors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: activo ? AppColors.black : AppColors.warmBorder),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: !habilitado
                    ? const Color(0xFFCFC8C1)
                    : (activo ? AppColors.white : AppColors.black),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('Todas', null),
          for (var e = 5; e >= 1; e--)
            chip('$e★', e, habilitado: (desglose[e] ?? 0) > 0),
        ],
      ),
    );
  }
}

/// La tarjeta que definió la usuaria el 28/8: nombre a la izquierda y
/// estrellas a la derecha arriba; clase y fecha en itálica debajo; el texto
/// abajo.
///
/// Fallback: hoy TODAS las reseñas tienen `clase_id` null (el pedido de
/// reseña lleva al perfil del estudio, no a la clase), así que sin clase se
/// muestra sólo la fecha en vez de dejar la línea vacía.
class ResenaCard extends StatelessWidget {
  final Map<String, dynamic> resena;

  /// Ya resuelto según quién mira. Null → "Usuario Aura".
  final String? nombre;

  const ResenaCard({super.key, required this.resena, this.nombre});

  @override
  Widget build(BuildContext context) {
    final rating = (resena['rating'] as num?)?.toInt() ?? 0;
    final clase = resena['clases'] as Map<String, dynamic>?;
    final claseNombre = clase?['nombre']?.toString().trim();
    // La profe se muestra SOLO si está: es texto libre y está cargada en
    // ~la mitad de las clases. Sin ranking por profe — con ese nivel de
    // completitud un promedio por instructor sería engañoso.
    final profe = clase?['instructor']?.toString().trim();
    final creada = DateTime.tryParse(resena['created_at']?.toString() ?? '');
    final editada = () {
      final c = DateTime.tryParse(resena['created_at']?.toString() ?? '');
      final u = DateTime.tryParse(resena['updated_at']?.toString() ?? '');
      return c != null && u != null && u.isAfter(c.add(const Duration(minutes: 1)));
    }();

    final fecha =
        creada == null ? '' : DateFormat('d MMM', 'es').format(creada);
    final subtitulo = [
      if (claseNombre != null && claseNombre.isNotEmpty)
        profe != null && profe.isNotEmpty
            ? '$claseNombre con $profe'
            : claseNombre,
      if (fecha.isNotEmpty) fecha,
      if (editada) 'editada',
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  nombre?.trim().isNotEmpty == true
                      ? nombre!.trim()
                      : 'Usuario Aura',
                  style: const TextStyle(
                    color: AppColors.black,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _Estrellas(rating: rating, size: 15),
            ],
          ),
          if (subtitulo.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              subtitulo,
              style: const TextStyle(
                color: AppColors.grey,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            resena['comentario']?.toString().trim() ?? '',
            style: const TextStyle(
              color: Color(0xFF5E584F),
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _Estrellas extends StatelessWidget {
  final int rating;
  final double size;

  const _Estrellas({required this.rating, required this.size});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
            size: size,
            color: i <= rating ? AppColors.warning : const Color(0xFFDDD6CE),
          ),
      ],
    );
  }
}
