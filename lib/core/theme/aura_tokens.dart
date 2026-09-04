// Los números del diseño de Aura, en un solo lugar.
//
// De dónde salen (4/9/2026): NO son inventados. Son los que ya usaba
// `AuraGestionDesign` en las dos pantallas de gestión del estudio, que era el
// único rincón de la app con un sistema. La auditoría de diseño encontró que
// el lado de la ALUMNA no lo tenía, y el resultado eran, en 9 pantallas:
// 6 márgenes de página distintos, 14 radios de borde, 19 tamaños de letra y
// 8 sombras con parámetros únicos. Eso es lo que el ojo lee como "amateur".
//
// `AuraGestionDesign` ahora delega acá, así que los dos lados no se pueden
// separar de nuevo.
//
// Lo que NO vive acá, a propósito: los COLORES, que siguen en `AppColors`
// (incluida la firma de la marca, negro sobre naranja, que no se toca).

import 'package:flutter/material.dart';

/// Espaciado. Escala de 4, que es la que el ojo lee como ritmo.
class AuraEspacio {
  AuraEspacio._();

  /// El margen lateral de una pantalla. UNO solo para toda la app.
  static const double margen = 20;

  /// Entre dos secciones distintas.
  static const double seccion = 24;

  /// Entre el título de una sección y su contenido.
  static const double tituloAContenido = 14;

  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Padding lateral de página, listo para usar.
  static const EdgeInsets paddingPagina = EdgeInsets.symmetric(
    horizontal: margen,
  );
}

/// Radios. Tres escalones y una pastilla: alcanza para todo.
class AuraRadio {
  AuraRadio._();

  /// Chips, badges y cosas chicas.
  static const double chip = 8;

  /// Botones y campos.
  static const double boton = 12;

  /// Tarjetas y hojas.
  static const double tarjeta = 16;

  /// Completamente redondeado. Antes convivían tres literales para lo mismo
  /// (999, 9999 y 99).
  static const double pastilla = 999;

  static BorderRadius get rChip => BorderRadius.circular(chip);
  static BorderRadius get rBoton => BorderRadius.circular(boton);
  static BorderRadius get rTarjeta => BorderRadius.circular(tarjeta);
  static BorderRadius get rPastilla => BorderRadius.circular(pastilla);
}

/// Sombras. Una sola, suave. Antes había 8 combinaciones únicas y cada tarjeta
/// flotaba distinto.
class AuraSombra {
  AuraSombra._();

  static const BoxShadow suave = BoxShadow(
    color: Color(0x141A1A1A),
    blurRadius: 12,
    offset: Offset(0, 2),
  );

  static const List<BoxShadow> tarjeta = [suave];
}

/// La escala tipográfica: cinco escalones, no diecinueve.
///
/// Antes convivían 8 tamaños contiguos (11, 12, 13, 14, 15, 16, 17 y 18), que
/// no es una escala: sin saltos, nada resalta sobre nada. Los pesos también se
/// acotan: casi todo estaba en 700.
class AuraTipo {
  AuraTipo._();

  /// Etiquetas en mayúscula, con tracking. Encabeza secciones y tarjetas.
  static const double etiqueta = 11;

  /// Texto secundario: estudio, dirección, fecha.
  static const double secundario = 13;

  /// El cuerpo.
  static const double cuerpo = 15;

  /// Títulos de tarjeta y de sección.
  static const double titulo = 18;

  /// Titulares de pantalla.
  static const double display = 26;

  /// El estilo de las etiquetas de sección ("CERCA TUYO", "ESTUDIOS").
  ///
  /// Es el `sectionLabelStyle` que el sistema del estudio ya usaba: 13 px con
  /// tracking. En el Inicio esas etiquetas venían de `titleMedium`, o sea 18
  /// px en mayúscula y negrita: gritaban más que los nombres de las clases,
  /// que son lo que hay que leer.
  static const TextStyle estiloEtiqueta = TextStyle(
    fontSize: secundario,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.5,
  );
}
