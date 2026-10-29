// La landing (#/landing), rehecha el 29/10/2026 para la pauta de Meta.
//
// El público es quien quiere ENTRENAR, no los estudios: antes el botón naranja
// decía "Soy un estudio". Ahora hay un solo camino fuerte (registrarse) y
// "Soy un estudio" queda abajo, como link gris.
//
// Todos los datos van escritos a mano a propósito (decisión de Sofía): nada se
// lee de la base. Si cambian, se cambian acá. Al 29/10/2026:
//   · Pack Prueba: 20 créditos, $22.000 (pricing_credit_packs), vence a los
//     30 días (vencimiento_dias).
//   · 20% off en la primera compra: $17.600. El porcentaje real vive en
//     configuracion_global 'descuento_primera_compra_pct'. Si se apaga allá,
//     HAY QUE SACARLO DE ACÁ (las dos menciones: arriba y la tarjeta).
//   · Las clases cargadas van de 11 a 20 créditos.
//   · Cancelar hasta 12 h antes devuelve los créditos en TODOS los estudios
//     (la ventana es de 12 h, salvo tres que la tienen más corta: 8 y 10 h).
//
// Regla de diseño: un solo botón naranja por pantalla (por eso "Crear mi
// cuenta" va en blanco), y sólo tokens de marca.
//
// Pantalla grande (desde 900 px, 29/10/2026): contenido hasta 1040 px, título
// y bajada más grandes, botones de 330 px como máximo, las 6 fotos en una fila,
// los pasos en 3 columnas y la tarjeta de precio de 430 px como máximo. Abajo
// de 900 px queda igual que antes.
//
// Movimiento (29/10/2026):
//   · Al abrir, el bloque de arriba entra escalonado (80 ms entre cada pieza,
//     500 ms cada una). "Empezar ahora" termina de aparecer a los 740 ms.
//   · El resplandor naranja de arriba late cada 8 s, casi imperceptible. Es lo
//     ÚNICO que se mueve solo.
//   · Cada bloque aparece una sola vez cuando entra en pantalla; las fotos y
//     los pasos, de a uno (70 ms).
//   · En computadora, las fotos se agrandan un 7% con el mouse encima.
//   · Con "reducir movimiento" activado en el sistema no se mueve nada.
// Nada empuja el contenido: cada pieza ocupa su lugar desde el principio y lo
// que cambia es sólo su opacidad y un corrimiento que no afecta a las demás.

import 'dart:async';

import 'package:flutter/foundation.dart'
    show ValueListenable, kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/aura_tokens.dart';
import '../../utils/descarga_app.dart';
import '../../utils/movimiento_reducido_stub.dart'
    if (dart.library.js_interop) '../../utils/movimiento_reducido_web.dart';

/// Desde este ancho la landing usa el diseño de computadora.
const double kLandingCorteEscritorio = 900;

/// Las 6 fotos, en el orden pedido. Las imágenes son de 600×600.
const _estudios = [
  ('Citra Barre', 'assets/images/landing/citra-barre.jpg'),
  ('Ambra', 'assets/images/landing/ambra.jpg'),
  ('Rock Studios', 'assets/images/landing/rock-studios.jpg'),
  ('YOYO Yoga', 'assets/images/landing/yoyo-yoga.jpg'),
  ('PUR Lagree', 'assets/images/landing/la-pur.jpg'),
  ('Fit Pilates', 'assets/images/landing/fit-pilates.jpg'),
];

/// Lo que dura cada aparición, y la distancia desde la que sube.
const _kDuracionAparicion = Duration(milliseconds: 500);
const double _kSubida = 18;

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  void _irARegistro(BuildContext context) => context.go('/register');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final grande = constraints.maxWidth >= kLandingCorteEscritorio;
            // Entre bloques: 64 en celular; en computadora, unos 60 más.
            final double entreBloques = grande ? 124 : 64;
            return SingleChildScrollView(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // El resplandor va DETRÁS de todo y no ocupa lugar.
                  Positioned(
                    top: grande ? -260 : -170,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Center(
                        child: _Resplandor(diametro: grande ? 900 : 520),
                      ),
                    ),
                  ),
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: grande ? 1040 : 440,
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: grande ? 32 : 20,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: grande ? 36 : 28),
                            _Arriba(
                              grande: grande,
                              onEmpezar: () => _irARegistro(context),
                            ),
                            SizedBox(height: entreBloques),
                            _Estudios(grande: grande),
                            SizedBox(height: entreBloques),
                            _AsiFunciona(grande: grande),
                            SizedBox(height: entreBloques),
                            _CuantoSale(
                              grande: grande,
                              onComprar: () => _irARegistro(context),
                            ),
                            SizedBox(height: entreBloques),
                            _Cierre(
                              grande: grande,
                              onCrear: () => _irARegistro(context),
                            ),
                            SizedBox(height: grande ? 48 : 32),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── Movimiento ──────────────────────────────────────────────────────────────

/// ¿La persona pidió "reducir movimiento" en el sistema? En la web se mira
/// también el navegador: Flutter web no lo pasa a MediaQuery.
final bool _navegadorSinMovimiento = navegadorPideMenosMovimiento();
bool _sinMovimiento(BuildContext context) =>
    _navegadorSinMovimiento ||
    (MediaQuery.maybeDisableAnimationsOf(context) ?? false);

/// Avisa UNA vez cuando su contenido entra en pantalla. Mira la posición al
/// dibujarse y cada vez que se scrollea; después de avisar se desengancha.
class _Disparador extends StatefulWidget {
  final ValueNotifier<bool> disparo;
  final Widget child;

  const _Disparador({required this.disparo, required this.child});

  @override
  State<_Disparador> createState() => _DisparadorState();
}

class _DisparadorState extends State<_Disparador> {
  ScrollPosition? _posicion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _posicion?.removeListener(_mirar);
    _posicion = Scrollable.maybeOf(context)?.position;
    _posicion?.addListener(_mirar);
    WidgetsBinding.instance.addPostFrameCallback((_) => _mirar());
  }

  @override
  void didUpdateWidget(covariant _Disparador oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Cambió el tamaño de la ventana: puede haber entrado sin scrollear.
    WidgetsBinding.instance.addPostFrameCallback((_) => _mirar());
  }

  void _mirar() {
    if (!mounted || widget.disparo.value) return;
    final caja = context.findRenderObject();
    if (caja is! RenderBox || !caja.attached || !caja.hasSize) return;
    final arriba = caja.localToGlobal(Offset.zero).dy;
    final alto = MediaQuery.sizeOf(context).height;
    // Entra cuando su borde de arriba pasa el 90% de la pantalla.
    if (arriba < alto * 0.9) {
      widget.disparo.value = true;
      _posicion?.removeListener(_mirar);
      _posicion = null;
    }
  }

  @override
  void dispose() {
    _posicion?.removeListener(_mirar);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Fundido de abajo hacia arriba, una sola vez, cuando [disparo] se prende
/// (más [demora]). Ocupa su lugar desde el principio: no empuja nada.
class _Aparece extends StatefulWidget {
  final ValueListenable<bool> disparo;
  final Duration demora;
  final Widget child;

  const _Aparece({
    required this.disparo,
    required this.child,
    this.demora = Duration.zero,
  });

  @override
  State<_Aparece> createState() => _ApareceState();
}

class _ApareceState extends State<_Aparece>
    with SingleTickerProviderStateMixin {
  // Se crean siempre en initState (no `late` perezoso): con "reducir
  // movimiento" nunca se usan, y crearlas recién en dispose tiraba error.
  late final AnimationController _c;
  late final Animation<double> _v;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _kDuracionAparicion);
    _v = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    widget.disparo.addListener(_alDisparar);
    _alDisparar();
  }

  void _alDisparar() {
    if (!widget.disparo.value || _timer != null || _c.value > 0) return;
    widget.disparo.removeListener(_alDisparar);
    _timer = Timer(widget.demora, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    widget.disparo.removeListener(_alDisparar);
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_sinMovimiento(context)) return widget.child;
    return AnimatedBuilder(
      animation: _v,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _v.value,
        child: Transform.translate(
          offset: Offset(0, _kSubida * (1 - _v.value)),
          child: child,
        ),
      ),
    );
  }
}

/// Un grupo que aparece cuando entra en pantalla. [construir] recibe el
/// disparo para que cada pieza decida su demora (las fotos, de a una).
class _AlEntrar extends StatefulWidget {
  final Widget Function(ValueListenable<bool> disparo) construir;

  const _AlEntrar({required this.construir});

  /// Atajo: el bloque entero de una vez.
  factory _AlEntrar.bloque(Widget child) => _AlEntrar(
    construir: (d) => _Aparece(disparo: d, child: child),
  );

  @override
  State<_AlEntrar> createState() => _AlEntrarState();
}

class _AlEntrarState extends State<_AlEntrar> {
  final _disparo = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _disparo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _Disparador(disparo: _disparo, child: widget.construir(_disparo));
}

/// El resplandor naranja de arriba. Late MUY lento (8 s ida y vuelta),
/// creciendo y achicándose apenas, con un cambio chico de opacidad.
class _Resplandor extends StatefulWidget {
  final double diametro;

  const _Resplandor({required this.diametro});

  @override
  State<_Resplandor> createState() => _ResplandorState();
}

class _ResplandorState extends State<_Resplandor>
    with SingleTickerProviderStateMixin {
  // 4 s de ida + 4 s de vuelta = un ciclo de 8 s.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );
  late final Animation<double> _v = CurvedAnimation(
    parent: _c,
    curve: Curves.easeInOut,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sinMovimiento(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _disco(double alfa) => Container(
    width: widget.diametro,
    height: widget.diametro,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [
          AppColors.primary.withValues(alpha: alfa),
          AppColors.primary.withValues(alpha: 0),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_sinMovimiento(context)) return _disco(0.16);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _v,
        builder: (context, _) => Transform.scale(
          scale: 0.96 + 0.06 * _v.value,
          child: _disco(0.14 + 0.05 * _v.value),
        ),
      ),
    );
  }
}

// ── Piezas comunes ──────────────────────────────────────────────────────────

/// En computadora los botones no van de ancho completo: 330 px, centrados.
class _AnchoBoton extends StatelessWidget {
  final bool grande;
  final Widget child;

  const _AnchoBoton({required this.grande, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!grande) return child;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 330),
        child: child,
      ),
    );
  }
}

/// El único botón naranja de cada pantalla.
class _BotonNaranja extends StatelessWidget {
  final String texto;
  final VoidCallback onPressed;
  final bool grande;

  const _BotonNaranja({
    required this.texto,
    required this.onPressed,
    this.grande = false,
  });

  @override
  Widget build(BuildContext context) {
    return _AnchoBoton(
      grande: grande,
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AuraRadio.boton),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: Text(texto),
        ),
      ),
    );
  }
}

class _TituloSeccion extends StatelessWidget {
  final String texto;

  const _TituloSeccion(this.texto);

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: const TextStyle(
        color: AppColors.primary,
        fontSize: AuraTipo.etiqueta,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    );
  }
}

// ── 0. Logo ─────────────────────────────────────────────────────────────────

/// El logo de Aura: el mismo cuadrado con el círculo que tenía la portada,
/// más chico, y la marca al lado.
class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.black, width: 2),
                  ),
                ),
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: AppColors.black,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          'AURA.',
          style: TextStyle(
            color: AppColors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }
}

// ── 1. Arriba ───────────────────────────────────────────────────────────────

/// Entra al abrir la página, escalonado: logo, título, bajada, botón y la
/// línea gris, con 80 ms entre cada uno.
class _Arriba extends StatefulWidget {
  final VoidCallback onEmpezar;
  final bool grande;

  const _Arriba({required this.onEmpezar, required this.grande});

  @override
  State<_Arriba> createState() => _ArribaState();
}

class _ArribaState extends State<_Arriba> {
  // Prendido desde el principio: el bloque de arriba no espera al scroll.
  final _alAbrir = ValueNotifier<bool>(true);

  @override
  void dispose() {
    _alAbrir.dispose();
    super.dispose();
  }

  Widget _pieza(int orden, Widget child) => _Aparece(
    disparo: _alAbrir,
    demora: Duration(milliseconds: 80 * orden),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final grande = widget.grande;
    final alineacion = grande ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment: grande
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        _pieza(0, const _Logo()),
        SizedBox(height: grande ? 64 : 36),
        _pieza(
          1,
          Text.rich(
            const TextSpan(
              children: [
                TextSpan(text: 'Un pack.\n'),
                TextSpan(
                  text: 'Todos los estudios.',
                  style: TextStyle(color: AppColors.primary),
                ),
              ],
            ),
            textAlign: alineacion,
            style: TextStyle(
              color: AppColors.white,
              fontSize: grande ? 54 : 38,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
        ),
        SizedBox(height: grande ? 20 : 16),
        _pieza(
          2,
          ConstrainedBox(
            // En computadora, unas 44 letras por línea como máximo.
            constraints: BoxConstraints(
              maxWidth: grande ? 460 : double.infinity,
            ),
            child: Text(
              'Comprás créditos una vez y reservás en estudios de Buenos Aires. '
              'Pilates, yoga, spinning, barre y más.',
              textAlign: alineacion,
              style: TextStyle(
                color: AppColors.mutedText,
                fontSize: grande ? 19 : 17,
                height: 1.45,
              ),
            ),
          ),
        ),
        SizedBox(height: grande ? 36 : 28),
        _pieza(
          3,
          _BotonNaranja(
            texto: 'Empezar ahora',
            onPressed: widget.onEmpezar,
            grande: grande,
          ),
        ),
        const SizedBox(height: 12),
        _pieza(
          4,
          const Center(
            child: Text(
              'Sin permanencia · 20% off en tu primera compra',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.grey,
                fontSize: AuraTipo.secundario,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── 2. Los estudios ─────────────────────────────────────────────────────────

class _Estudios extends StatelessWidget {
  final bool grande;

  const _Estudios({required this.grande});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AlEntrar.bloque(const _TituloSeccion('DÓNDE PODÉS ENTRENAR')),
        const SizedBox(height: 14),
        // Las fotos entran de a una, 70 ms entre cada una.
        _AlEntrar(
          construir: (disparo) => GridView.count(
            crossAxisCount: grande ? 6 : 3,
            mainAxisSpacing: grande ? 12 : 8,
            crossAxisSpacing: grande ? 12 : 8,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final (i, (nombre, foto)) in _estudios.indexed)
                _Aparece(
                  disparo: disparo,
                  demora: Duration(milliseconds: 70 * i),
                  child: _FotoEstudio(nombre: nombre, foto: foto),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _AlEntrar.bloque(
          const Text(
            'También Sitio Pilates, EQUMM, Pura Spot, Barre Estudio y más.',
            style: TextStyle(
              color: AppColors.mutedText,
              fontSize: AuraTipo.secundario,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _FotoEstudio extends StatefulWidget {
  final String nombre;
  final String foto;

  const _FotoEstudio({required this.nombre, required this.foto});

  @override
  State<_FotoEstudio> createState() => _FotoEstudioState();
}

class _FotoEstudioState extends State<_FotoEstudio> {
  bool _mouseEncima = false;

  @override
  Widget build(BuildContext context) {
    // Con el mouse encima la FOTO se agranda un 7% dentro de su cuadrado: el
    // cuadrado no cambia de tamaño y no corre a los de al lado.
    final agrandar = _mouseEncima && !_sinMovimiento(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _mouseEncima = true),
      onExit: (_) => setState(() => _mouseEncima = false),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AuraRadio.boton),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedScale(
              scale: agrandar ? 1.07 : 1,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              child: Image.asset(
                widget.foto,
                fit: BoxFit.cover,
                // Si una foto no carga, queda el cuadrado oscuro con el nombre.
                errorBuilder: (_, _, _) =>
                    const ColoredBox(color: AppColors.blackSoft),
              ),
            ),
            // Degradé oscuro abajo para que el nombre se lea sobre cualquier
            // foto.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.45, 1],
                  colors: [
                    AppColors.blackDeep.withValues(alpha: 0),
                    AppColors.blackDeep.withValues(alpha: 0.85),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 7,
              child: Text(
                widget.nombre,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 3. Así funciona ─────────────────────────────────────────────────────────

const _pasos = [
  ('Comprás un pack de créditos', 'Una sola vez.'),
  (
    'Elegís la clase que quieras',
    'Buscás por disciplina, barrio o estudio, y ves cuántos lugares quedan.',
  ),
  (
    'Reservás y vas',
    'Llegás con tu código en la app y listo. Si cancelás hasta 12 horas '
        'antes, te devolvemos los créditos.',
  ),
];

class _AsiFunciona extends StatelessWidget {
  final bool grande;

  const _AsiFunciona({required this.grande});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AlEntrar.bloque(const _TituloSeccion('ASÍ FUNCIONA')),
        SizedBox(height: grande ? 24 : 18),
        // Los tres pasos entran de a uno, 70 ms entre cada uno.
        _AlEntrar(
          construir: (disparo) {
            Widget paso(int i) => _Aparece(
              disparo: disparo,
              demora: Duration(milliseconds: 70 * i),
              child: _Paso(
                numero: i + 1,
                titulo: _pasos[i].$1,
                texto: _pasos[i].$2,
                vertical: grande,
              ),
            );
            if (grande) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < _pasos.length; i++) ...[
                    if (i > 0) const SizedBox(width: 40),
                    Expanded(child: paso(i)),
                  ],
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < _pasos.length; i++) ...[
                  if (i > 0) const SizedBox(height: 22),
                  paso(i),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Paso extends StatelessWidget {
  final int numero;
  final String titulo;
  final String texto;

  /// En computadora el número va arriba del texto, no al costado.
  final bool vertical;

  const _Paso({
    required this.numero,
    required this.titulo,
    required this.texto,
    this.vertical = false,
  });

  @override
  Widget build(BuildContext context) {
    final circulo = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.primary, width: 1.6),
      ),
      child: Center(
        child: Text(
          '$numero',
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: AuraTipo.cuerpo,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
    final textos = [
      Text(
        titulo,
        style: const TextStyle(
          color: AppColors.white,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        texto,
        style: const TextStyle(
          color: AppColors.mutedText,
          fontSize: AuraTipo.cuerpo,
          height: 1.45,
        ),
      ),
    ];
    if (vertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [circulo, const SizedBox(height: 14), ...textos],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        circulo,
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [const SizedBox(height: 4), ...textos],
          ),
        ),
      ],
    );
  }
}

// ── 4. Cuánto sale ──────────────────────────────────────────────────────────

class _CuantoSale extends StatelessWidget {
  final VoidCallback onComprar;
  final bool grande;

  const _CuantoSale({required this.onComprar, required this.grande});

  @override
  Widget build(BuildContext context) {
    final bloque = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TituloSeccion('CUÁNTO SALE'),
        const SizedBox(height: 14),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.blackDeep,
            borderRadius: BorderRadius.circular(AuraRadio.tarjeta),
            border: Border.all(color: AppColors.textoSecundario),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // La cintita.
              Container(
                color: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: const Text(
                  '20% OFF en tu primera compra',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: AuraTipo.secundario,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pack Prueba · 20 créditos',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: AuraTipo.titulo,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Si en un celular muy angosto no entra, se achica en
                    // vez de cortarse.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '\$22.000',
                            style: TextStyle(
                              color: AppColors.grey,
                              fontSize: 18,
                              decoration: TextDecoration.lineThrough,
                              decorationColor: AppColors.grey,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text(
                            '\$17.600',
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Las clases van de 11 a 20 créditos. Vencen a los 30 días.',
                      style: TextStyle(
                        color: AppColors.mutedText,
                        fontSize: AuraTipo.secundario,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Dentro de la tarjeta (430 px) el botón va al ancho de
                    // la tarjeta: ya no es de 1000 px.
                    _BotonNaranja(
                      texto: 'Quiero mis créditos',
                      onPressed: onComprar,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final tarjeta = _AlEntrar.bloque(bloque);
    if (!grande) return tarjeta;
    // En computadora la tarjeta no se estira: 430 px, centrada.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: tarjeta,
      ),
    );
  }
}

// ── 5. Cierre ───────────────────────────────────────────────────────────────

class _Cierre extends StatelessWidget {
  final VoidCallback onCrear;
  final bool grande;

  const _Cierre({required this.onCrear, required this.grande});

  @override
  Widget build(BuildContext context) {
    return _AlEntrar.bloque(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Empezá hoy',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.white,
              fontSize: grande ? 38 : 30,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Creás tu cuenta en un minuto y reservás tu primera clase.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.mutedText,
              fontSize: AuraTipo.cuerpo,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 24),
          // Blanco, no naranja: en el celular entra en la misma pantalla que
          // "Quiero mis créditos", y la regla es un solo naranja por pantalla.
          _AnchoBoton(
            grande: grande,
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: onCrear,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.white,
                  foregroundColor: AppColors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AuraRadio.boton),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Crear mi cuenta'),
              ),
            ),
          ),
          const _ChapitasTiendas(),
          const SizedBox(height: 36),
          // Los tres en una línea, del mismo tamaño. FittedBox: en un celular
          // muy angosto se achican juntos en vez de partirse en dos renglones.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LinkGris(
                  texto: 'Ya tengo cuenta',
                  onTap: () => context.go('/login'),
                ),
                const _Separador(),
                _LinkGris(
                  texto: 'Explorar sin cuenta',
                  onTap: () => context.go('/explorar'),
                ),
                const _Separador(),
                _LinkGris(
                  texto: 'Soy un estudio',
                  onTap: () => context.go('/login?rol=estudio'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkGris extends StatelessWidget {
  final String texto;
  final VoidCallback onTap;

  const _LinkGris({required this.texto, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AuraRadio.chip),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Text(
          texto,
          style: const TextStyle(
            color: AppColors.grey,
            fontSize: AuraTipo.secundario,
          ),
        ),
      ),
    );
  }
}

class _Separador extends StatelessWidget {
  const _Separador();

  @override
  Widget build(BuildContext context) {
    return const Text(
      '·',
      style: TextStyle(color: AppColors.grey, fontSize: AuraTipo.secundario),
    );
  }
}

/// Las dos chapitas de tienda, chicas y con borde gris. Dentro de la app
/// nativa no se muestran: ya la tienen instalada (tiendasParaLanding).
class _ChapitasTiendas extends StatelessWidget {
  const _ChapitasTiendas();

  @override
  Widget build(BuildContext context) {
    final tiendas = tiendasParaLanding(defaultTargetPlatform, esWeb: kIsWeb);
    if (tiendas.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final t in tiendas) ...[
            if (t != tiendas.first) const SizedBox(width: 10),
            _Chapita(tienda: t),
          ],
        ],
      ),
    );
  }
}

class _Chapita extends StatelessWidget {
  final BotonTienda tienda;

  const _Chapita({required this.tienda});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => launchUrl(
        Uri.parse(tienda.url),
        mode: LaunchMode.externalApplication,
      ),
      icon: Icon(
        tienda.tienda == Tienda.appStore ? Icons.apple : Icons.shop_rounded,
        size: 16,
      ),
      label: Text(tienda.etiqueta),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.mutedText,
        side: const BorderSide(color: AppColors.textoSecundario),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        minimumSize: const Size(0, 38),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AuraRadio.pastilla),
        ),
        textStyle: const TextStyle(
          fontSize: AuraTipo.secundario,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
