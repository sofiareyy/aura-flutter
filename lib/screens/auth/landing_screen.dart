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
// Regla de diseño: un solo botón naranja por pantalla, y sólo tokens de marca.

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/aura_tokens.dart';
import '../../utils/descarga_app.dart';

/// Las 6 fotos, en el orden pedido. Las imágenes son de 600×600.
const _estudios = [
  ('Citra Barre', 'assets/images/landing/citra-barre.jpg'),
  ('Ambra', 'assets/images/landing/ambra.jpg'),
  ('Rock Studios', 'assets/images/landing/rock-studios.jpg'),
  ('YOYO Yoga', 'assets/images/landing/yoyo-yoga.jpg'),
  ('PUR Lagree', 'assets/images/landing/la-pur.jpg'),
  ('Fit Pilates', 'assets/images/landing/fit-pilates.jpg'),
];

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  void _irARegistro(BuildContext context) => context.go('/register');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 28),
                    const _Logo(),
                    const SizedBox(height: 36),
                    _Arriba(onEmpezar: () => _irARegistro(context)),
                    const SizedBox(height: 64),
                    const _Estudios(),
                    const SizedBox(height: 64),
                    const _AsiFunciona(),
                    const SizedBox(height: 64),
                    _CuantoSale(onComprar: () => _irARegistro(context)),
                    // Aire de sobra: así el botón de la tarjeta y el del
                    // cierre no entran juntos en la pantalla del celular.
                    const SizedBox(height: 120),
                    _Cierre(onCrear: () => _irARegistro(context)),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Piezas comunes ──────────────────────────────────────────────────────────

/// El único botón naranja de cada pantalla.
class _BotonNaranja extends StatelessWidget {
  final String texto;
  final VoidCallback onPressed;

  const _BotonNaranja({required this.texto, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
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
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        child: Text(texto),
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

class _Arriba extends StatelessWidget {
  final VoidCallback onEmpezar;

  const _Arriba({required this.onEmpezar});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text.rich(
          TextSpan(
            children: [
              TextSpan(text: 'Un pack.\n'),
              TextSpan(
                text: 'Todos los estudios.',
                style: TextStyle(color: AppColors.primary),
              ),
            ],
          ),
          style: TextStyle(
            color: AppColors.white,
            fontSize: 38,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Comprás créditos una vez y reservás en estudios de Buenos Aires. '
          'Pilates, yoga, spinning, barre y más.',
          style: TextStyle(
            color: AppColors.mutedText,
            fontSize: 17,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 28),
        _BotonNaranja(texto: 'Empezar ahora', onPressed: onEmpezar),
        const SizedBox(height: 12),
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
      ],
    );
  }
}

// ── 2. Los estudios ─────────────────────────────────────────────────────────

class _Estudios extends StatelessWidget {
  const _Estudios();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TituloSeccion('DÓNDE PODÉS ENTRENAR'),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final (nombre, foto) in _estudios)
              _FotoEstudio(nombre: nombre, foto: foto),
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          'También Sitio Pilates, EQUMM, Pura Spot, Barre Estudio y más.',
          style: TextStyle(
            color: AppColors.mutedText,
            fontSize: AuraTipo.secundario,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _FotoEstudio extends StatelessWidget {
  final String nombre;
  final String foto;

  const _FotoEstudio({required this.nombre, required this.foto});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AuraRadio.boton),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            foto,
            fit: BoxFit.cover,
            // Si una foto no carga, queda el cuadrado oscuro con el nombre.
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: AppColors.blackSoft),
          ),
          // Degradé oscuro abajo para que el nombre se lea sobre cualquier foto.
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
              nombre,
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
    );
  }
}

// ── 3. Así funciona ─────────────────────────────────────────────────────────

class _AsiFunciona extends StatelessWidget {
  const _AsiFunciona();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TituloSeccion('ASÍ FUNCIONA'),
        SizedBox(height: 18),
        _Paso(
          numero: 1,
          titulo: 'Comprás un pack de créditos',
          texto: 'Una sola vez.',
        ),
        SizedBox(height: 22),
        _Paso(
          numero: 2,
          titulo: 'Elegís la clase que quieras',
          texto:
              'Buscás por disciplina, barrio o estudio, y ves cuántos '
              'lugares quedan.',
        ),
        SizedBox(height: 22),
        _Paso(
          numero: 3,
          titulo: 'Reservás y vas',
          texto:
              'Llegás con tu código en la app y listo. Si cancelás hasta '
              '12 horas antes, te devolvemos los créditos.',
        ),
      ],
    );
  }
}

class _Paso extends StatelessWidget {
  final int numero;
  final String titulo;
  final String texto;

  const _Paso({
    required this.numero,
    required this.titulo,
    required this.texto,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
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
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
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
            ],
          ),
        ),
      ],
    );
  }
}

// ── 4. Cuánto sale ──────────────────────────────────────────────────────────

class _CuantoSale extends StatelessWidget {
  final VoidCallback onComprar;

  const _CuantoSale({required this.onComprar});

  @override
  Widget build(BuildContext context) {
    return Column(
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
                    const Row(
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
  }
}

// ── 5. Cierre ───────────────────────────────────────────────────────────────

class _Cierre extends StatelessWidget {
  final VoidCallback onCrear;

  const _Cierre({required this.onCrear});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Empezá hoy',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.white,
            fontSize: 30,
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
        _BotonNaranja(texto: 'Crear mi cuenta', onPressed: onCrear),
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
