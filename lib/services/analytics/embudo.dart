import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'analytics_stub.dart'
    if (dart.library.js_interop) 'analytics_web.dart'
    as impl;

/// El embudo de la landing a la compra (5/11/2026).
///
///  1. ver_landing        LandingScreen, al abrirse.
///  2. clic_crear_cuenta  los botones de la landing que llevan al registro.
///  3. inicio_registro    la pantalla de registro, cuando empieza a completar
///                        (escribe en un campo o toca Google / Apple).
///  4. sign_up            la cuenta se creó (mail, o la vuelta de Google/Apple).
///  5. ver_clases         Explorar, la ficha de una clase o de un estudio.
///  6. ver_packs          la pantalla de packs.
///  7. begin_checkout     el link de Mercado Pago ya está armado y sale a pagar.
///  8. purchase           NO es de acá: lo manda el servidor cuando Mercado Pago
///                        confirma el pago (mp-webhook, _shared/ga4.ts).
///
/// A GA4 va sólo desde la web (web/aura-analytics.js le suma la campaña y el
/// usuario). Los pasos 5 y 6 además se anotan en la base (`embudo_pasos`, la
/// primera vez de cada cuenta, en web y en la app) para la vista
/// `metricas.embudo`.
///
/// Nunca lanza: medir no puede romper la app.
class Embudo {
  Embudo._();

  static bool _landing = false;
  static bool _inicioRegistro = false;
  static final Set<String> _pasosVistos = {};
  static final Set<String> _pasosEnBase = {};
  static String? _uid;
  static final Map<String, bool> _internaPorUid = {};

  static void landing() {
    if (_landing) return;
    _landing = true;
    _ga('ver_landing');
  }

  /// [boton]: 'principal' ("Crear mi cuenta gratis"), 'precio' ("Quiero mis
  /// créditos") o 'cierre'. Los tres llevan al registro; en GA4 se filtra por
  /// `boton` para ver sólo el principal.
  static void clicCrearCuenta(String boton) =>
      _ga('clic_crear_cuenta', {'boton': boton});

  /// [metodo]: 'email', 'google' o 'apple'. Una vez por carga.
  static void inicioRegistro(String metodo) {
    if (_inicioRegistro) return;
    _inicioRegistro = true;
    _ga('inicio_registro', {'method': metodo});
  }

  /// La cuenta se acaba de crear. Una sola vez por cuenta en este dispositivo,
  /// aunque la vuelta de OAuth recargue la página.
  static Future<void> registroCompletado({
    required String uid,
    required String metodo,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clave = 'embudo_sign_up_$uid';
      if (prefs.getBool(clave) == true) return;
      await prefs.setBool(clave, true);
      impl.usuario(uid);
      _ga('sign_up', {'method': metodo});
    } catch (e) {
      debugPrint('[Embudo] sign_up: $e');
    }
  }

  /// ¿La cuenta es nueva? Para la vuelta de Google / Apple, que no sabe si fue
  /// un registro o un login: nueva = creada hace menos de 10 minutos.
  static bool esCuentaNueva(String? createdAt, {DateTime? ahora}) {
    final alta = DateTime.tryParse(createdAt ?? '');
    if (alta == null) return false;
    final dif = (ahora ?? DateTime.now()).toUtc().difference(alta.toUtc());
    return !dif.isNegative && dif < const Duration(minutes: 10);
  }

  /// Qué paso del embudo es una ruta, o null.
  static String? pasoDeRuta(String path) {
    if (path == '/explorar' || path.startsWith('/clase/')) return 'ver_clases';
    if (path.startsWith('/estudio/')) {
      var resto = path.substring('/estudio/'.length);
      if (resto.endsWith('/resenas')) {
        resto = resto.substring(0, resto.length - '/resenas'.length);
      }
      if (int.tryParse(resto) != null) return 'ver_clases';
    }
    if (path == '/comprar-creditos') return 'ver_packs';
    return null;
  }

  /// Lo llama el listener del router en cada cambio de ruta (web y app).
  static void rutaCambio(String path) {
    final paso = pasoDeRuta(path);
    if (paso == null || _pasosVistos.contains(paso)) return;
    _pasosVistos.add(paso);
    _ga(paso);
    _anotarEnBase();
  }

  /// Al iniciar o cerrar sesión. Pone el usuario en GA, apaga GA si la cuenta
  /// es interna, y anota en la base los pasos que vio antes de entrar.
  static Future<void> sesion() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user?.id != _uid) {
        _uid = user?.id;
        impl.usuario(_uid);
      }
      if (user == null) return;
      if (kIsWeb && !_internaPorUid.containsKey(user.id)) {
        _internaPorUid[user.id] = false;
        final r = await Supabase.instance.client.rpc('soy_cuenta_interna');
        _internaPorUid[user.id] = r == true;
        if (r == true) impl.marcarInterna();
      }
      await _anotarEnBase();
    } catch (e) {
      debugPrint('[Embudo] sesión: $e');
    }
  }

  static Future<void> _anotarEnBase() async {
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser == null) return;
      for (final paso in _pasosVistos.difference(_pasosEnBase).toList()) {
        _pasosEnBase.add(paso);
        await client.rpc('registrar_paso_embudo', params: {
          'p_paso': paso,
          'p_plataforma': kIsWeb ? 'web' : defaultTargetPlatform.name,
        });
      }
    } catch (e) {
      debugPrint('[Embudo] no se pudo anotar el paso: $e');
    }
  }

  /// El link de Mercado Pago ya está y la persona sale a pagar.
  static void inicioCheckout({
    required String tipo,
    required String nombre,
    required int valor,
  }) {
    _ga('begin_checkout', {
      'currency': 'ARS',
      'value': valor,
      'items': [
        {'item_name': nombre, 'item_category': tipo, 'price': valor, 'quantity': 1},
      ],
    });
  }

  /// Lo que el checkout guarda en el pago para unir la compra a esta visita.
  /// Vacío fuera de la web o en un navegador de cuenta interna.
  static Map<String, dynamic> datosParaCheckout() {
    try {
      final d = jsonDecode(impl.datosCheckout());
      return d is Map<String, dynamic> ? d : const {};
    } catch (_) {
      return const {};
    }
  }

  static void _ga(String nombre, [Map<String, dynamic> params = const {}]) {
    if (!kIsWeb) return;
    try {
      impl.evento(nombre, jsonEncode(params));
    } catch (_) {}
  }
}
