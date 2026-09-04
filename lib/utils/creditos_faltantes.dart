// Qué se le dice a alguien cuando los créditos no le alcanzan.
//
// Existe para que los TRES lugares donde aparece esa situación digan lo mismo
// (4/9/2026): el renglón "Tu saldo" del detalle de clase, la hoja del paywall
// que sube al tocar Reservar, y la pantalla de confirmar reserva.
//
// Dos reglas que valen en los tres:
//   1. **Nunca un número negativo.** El detalle mostraba "Quedan -8 tras
//      reservar": una resta cruda. Lo que falta se dice en positivo.
//   2. **A quien es nueva se le explica el modelo.** "Créditos insuficientes"
//      no significa nada para alguien que llega de la pauta y todavía no sabe
//      qué es un crédito en Aura.

/// Cuántos créditos faltan para poder reservar. Nunca negativo: si alcanza,
/// es 0.
int creditosFaltantes({required int saldo, required int precio}) {
  final falta = precio - saldo;
  return falta > 0 ? falta : 0;
}

/// ¿Le alcanza?
bool alcanzaElSaldo({required int saldo, required int precio}) =>
    creditosFaltantes(saldo: saldo, precio: precio) == 0;

String _cr(int n) => n == 1 ? '1 crédito' : '$n créditos';

/// El renglón corto de "Tu saldo", en el detalle de clase.
///
/// Reemplaza al viejo `'Quedan ${saldo - precio} tras reservar'`, que con
/// saldo 0 y una clase de 8 mostraba **"Quedan -8 tras reservar"**.
String textoSaldoTrasReservar({required int saldo, required int precio}) {
  final faltan = creditosFaltantes(saldo: saldo, precio: precio);
  if (faltan > 0) return 'Te faltan ${_cr(faltan)}';
  return 'Quedan ${saldo - precio} tras reservar';
}

/// Título del paywall.
String tituloPaywall({required int saldo, required int precio}) {
  if (saldo <= 0) return 'Necesitás créditos para reservar';
  return 'Te faltan ${_cr(creditosFaltantes(saldo: saldo, precio: precio))}';
}

/// Cuerpo del paywall.
///
/// El corte por `saldo == 0` es un PROXY de "todavía no compró nunca", y es
/// deliberado: no hace falta una consulta más para saberlo, y la situación
/// visible es la misma. Quien tiene 0 créditos necesita que le expliquen de
/// qué se trata; quien tiene 2 ya sabe qué es un crédito y sólo quiere el
/// número que le falta.
String mensajePaywall({required int saldo, required int precio}) {
  if (saldo <= 0) {
    return 'Esta clase cuesta ${_cr(precio)}. En Aura comprás un pack de '
        'créditos y los usás en cualquier estudio, sin cuota mensual.';
  }
  return 'Esta clase cuesta ${_cr(precio)} y tenés $saldo. '
      'Comprá un pack y reservá al toque.';
}

/// El mismo aviso, en una línea, para la pantalla de confirmar reserva (donde
/// ya hay una tarjeta con el desglose y no hace falta repetir el precio).
String avisoConfirmarReserva({required int saldo, required int precio}) {
  final faltan = creditosFaltantes(saldo: saldo, precio: precio);
  if (faltan == 0) return '';
  if (saldo <= 0) {
    return 'Necesitás ${_cr(precio)} para reservar esta clase. '
        'Comprá un pack y volvés acá.';
  }
  return 'Te faltan ${_cr(faltan)} para esta reserva.';
}
