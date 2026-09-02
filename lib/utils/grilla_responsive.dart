/// Grilla de tarjetas de clase en pantallas anchas.
///
/// Inicio y Explorar son distintas A PROPÓSITO (decisión de diseño del 2/9):
/// Inicio es la **vidriera** —foto grande arriba, para enamorar— y Explorar es
/// el **buscador** —foto al costado, denso, para comparar muchas de un vistazo.
/// Por eso hay dos juegos de números y no uno solo.
///
/// Todo acá es función pura sobre un ancho: la lógica se testea sin levantar
/// widgets, y las pantallas sólo la consultan.
library;

/// Ancho tope del contenido de Inicio. Un poco más que el buscador: la
/// vidriera pide respirar. Sin esto, en un monitor de 1920 la tarjeta ocupaba
/// todo el ancho y la foto quedaba de 1900 × 132 (14:1, una banda).
const double anchoMaxVidriera = 1200;

/// Ancho tope del contenido de Explorar.
const double anchoMaxBuscador = 1100;

/// Proporción de la foto en la vidriera. 16:9 es la proporción de vidriera por
/// excelencia y, al ser PROPORCIÓN y no alto fijo, la foto no puede volver a
/// aplanarse por más ancha que quede la tarjeta.
const double proporcionFotoVidriera = 16 / 9;

/// Separación entre tarjetas, igual en las dos grillas.
const double gapGrilla = 16;

/// Columnas de la vidriera (Inicio). Con 3 la foto queda de ~390 px de ancho y
/// entran 6 clases sin scrollear; con 2 cada foto sería de casi 600 —linda,
/// pero se ve la mitad de la oferta.
int columnasVidriera(double ancho) {
  if (ancho >= 900) return 3;
  if (ancho >= 720) return 2;
  return 1;
}

/// Columnas del buscador (Explorar). Nunca más de 2: la tarjeta es ancha y
/// baja, con 3 el texto no entra.
int columnasBuscador(double ancho) => ancho >= 720 ? 2 : 1;

/// Ancho de cada celda de una grilla de [columnas] columnas dentro de [ancho],
/// descontando los espacios entre tarjetas.
double anchoCelda(double ancho, int columnas) {
  if (columnas <= 1) return ancho;
  return (ancho - gapGrilla * (columnas - 1)) / columnas;
}

// ── Buscador: la foto del costado ───────────────────────────────────────────
//
// La medida se decide por el ancho de LA TARJETA, no por el de la pantalla.
// Así una tarjeta ancha (desktop, o una sola columna en una ventana grande)
// recibe la foto 3:2 aprobada, y una angosta (teléfono, o el carrusel de
// experiencias de 320) se queda como está hoy — donde 186 px de foto se
// comerían más de la mitad del renglón y el texto no entraría.

/// A partir de este ancho de tarjeta entra la foto 3:2 sin ahogar el texto.
const double _anchoTarjetaConFotoGrande = 420;

const double _altoBuscadorAncho = 124;
const double _altoBuscadorAngosto = 112;

/// Alto de la tarjeta del buscador según su propio ancho.
double altoCardBuscador(double anchoCard) =>
    anchoCard >= _anchoTarjetaConFotoGrande
    ? _altoBuscadorAncho
    : _altoBuscadorAngosto;

/// Ancho de la foto del buscador. En la tarjeta ancha es 3:2 respecto del alto
/// (186 × 124); en la angosta se mantienen los 96 px de hoy.
double anchoFotoBuscador(double anchoCard) =>
    anchoCard >= _anchoTarjetaConFotoGrande ? _altoBuscadorAncho * 3 / 2 : 96;

/// Alto del bloque de texto de la tarjeta de Inicio (todo lo que está abajo de
/// la foto), en el peor caso: nombre de estudio de dos renglones.
///
/// No depende del ancho —los demás renglones son de una línea con ellipsis—,
/// así que alcanza con un número. Medido en 144 px contra la tarjeta real;
/// `tarjeta_inicio_test.dart` vuelve a medirlo y falla si algún día crece.
const double altoTextoVidriera = 148;

/// Alto de una tarjeta de vidriera de [anchoCard] px: la foto en 16:9 más el
/// texto.
double altoCardVidriera(double anchoCard) =>
    anchoCard / proporcionFotoVidriera + altoTextoVidriera;

/// Alto de los carruseles horizontales de Inicio, cuyas tarjetas miden 320.
/// Antes era 270 con la foto de alto fijo 132; con la foto en 16:9 la foto
/// sola ya mide 180.
final double altoCarruselVidriera = altoCardVidriera(320);

// ── Pantallas de detalle: perfil del estudio y detalle de clase ─────────────
//
// Las dos abren con una foto grande (el "hero") que hasta el 2/9 tenía alto
// FIJO en 300 px y ancho libre. En un teléfono eso daba 390 × 300 (1,3:1) y
// estaba bien, pero en un monitor de 1920 quedaba de 1920 × 300 = 6,4:1: de
// una foto apaisada normal se veía apenas el 25% del alto. Es el mismo bug
// que las tarjetas, en otras dos pantallas.

/// Ancho tope del contenido de las pantallas de detalle. Igual que el
/// buscador: el texto de la descripción a 1900 px de ancho tampoco se lee.
const double anchoMaxDetalle = 1100;

/// Proporción del hero: **2:1**.
///
/// La proporción es la que decide cuánto se recorta, y el ancho sólo decide
/// cuán alto termina siendo. De una foto apaisada típica (3:2) en 2:1 se ve el
/// **75%**; en 16:9 se vería el 84%, pero a 1100 px de ancho el hero mediría
/// 619 px de alto y se comería la pantalla entera antes del primer renglón de
/// texto. 2:1 deja 550 px: sigue siendo una foto, no una franja, y todavía
/// entra algo de contenido. Contra los 6,4:1 de hoy, se pasa de ver el 25% de
/// la foto a ver el 75%.
const double proporcionHero = 2;

/// Alto mínimo del hero: los 300 px de siempre. Debajo de 600 px de ancho
/// —cualquier teléfono— la fórmula da menos, así que el hero queda **igual
/// que hoy** y el arreglo no toca la app nativa.
const double altoHeroMin = 300;

/// Alto del hero para un ancho dado.
double altoHero(double ancho) {
  final proporcional = ancho / proporcionHero;
  return proporcional < altoHeroMin ? altoHeroMin : proporcional;
}

/// Ancho tope de las pantallas de un solo paso (confirmar reserva). Más
/// angosto que las de detalle: es una tarjeta con la clase, los créditos y un
/// botón, no una página para recorrer.
///
/// Sin esto, la foto de la clase —alto fijo 154 px, ancho libre— quedaba de
/// 12,2:1 en un monitor de 1920: se veía el 12% de una foto apaisada, justo en
/// la pantalla anterior a reservar. Peor que los heroes.
const double anchoMaxFormulario = 640;
