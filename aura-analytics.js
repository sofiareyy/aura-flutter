/*
 * Google Analytics 4 de somosaurapass.com — ÚNICO lugar donde vive el ID.
 *
 * Lo cargan en <head>, SINCRÓNICO y antes que cualquier otro script, todas las
 * páginas del sitio: la app Flutter (index.html) y las estáticas (descargar,
 * soporte, términos, privacidad, eliminar cuenta). Cambiar de propiedad =
 * cambiar MEASUREMENT_ID acá y en ningún otro lado.
 *
 * El ID de medición es público por diseño (viaja en cada hit): no es un
 * secreto. Acá no va ninguna clave privada ni API secret.
 *
 * Por qué gtag.js directo y no Firebase Analytics: en el proyecto de Firebase
 * sólo están registradas las apps de Android e iOS; Firebase no se inicializa
 * en web (ver main.dart). Sumar una app web a Firebase sería una segunda vía
 * hacia GA para lo mismo. Una sola etiqueta = un solo page_view por carga.
 *
 * QUÉ SE MIDE
 *  · page_view de la carga: lo manda `config`, acá mismo, con la URL tal como
 *    llegó (UTM incluidos) congelada ANTES de que arranque Flutter. Así nada
 *    —ni GoRouter ni un redirect— puede sacarle los UTM antes de medirlos.
 *  · page_view de cada cambio de ruta de la app: los manda Dart
 *    (lib/services/analytics/) llamando a `auraAnalytics.pageView`. El
 *    "page_view por historial" automático de GA no los duplica: compara la URL
 *    SIN el fragmento, y la app usa hash routing (#/home, #/clase/12), así que
 *    para GA la URL nunca cambia.
 *  · app_store_click: todo <a> que apunte a apps.apple.com se mide solo (un
 *    listener delegado, uno por clic) con el `data-placement` del enlace. Los
 *    botones de Flutter llaman a `auraAnalytics.appStoreClick`.
 *
 * RUTAS DE LA APP: GA arma el "page path" con la parte de la URL anterior al
 * '#', así que con hash routing TODA la app se vería como "/". Por eso las
 * rutas de Flutter se mandan como ruta virtual:
 *   somosaurapass.com/#/clase/12  ->  page_location .../clase/12
 */
(function () {
  "use strict";

  var MEASUREMENT_ID = "G-CLBKV39C1M";

  // Parámetros de la URL que SÍ se le pasan a GA. Todo lo demás se descarta:
  // por acá vuelve el login de Google (?code=...) y el de Mercado Pago
  // (?pago_id=...), y eso no tiene por qué terminar en Analytics.
  //   utm_*          campañas (Meta: source/medium/campaign/content)
  //   gclid...       auto-tagging de Google Ads, por si algún día se usa
  //   fbclid         lo agrega Meta a todo clic saliente
  //   c              campaña de la landing /descargar (ver descargar/index.html)
  var PARAMS_PERMITIDOS = /^(utm_[a-z_]+|gclid|gbraid|wbraid|fbclid|c)$/i;

  function queryLimpia(search) {
    var out = [];
    try {
      new URLSearchParams(search || "").forEach(function (v, k) {
        if (PARAMS_PERMITIDOS.test(k)) {
          out.push(encodeURIComponent(k) + "=" + encodeURIComponent(v));
        }
      });
    } catch (e) {}
    return out.length ? "?" + out.join("&") : "";
  }

  // Ruta de la app dentro del hash: "#/clase/12?x=1" -> "/clase/12". Un hash
  // que no empieza con "/" (p. ej. "#access_token=..." de un login) NO es una
  // ruta y NUNCA se manda.
  function rutaDelHash(hash) {
    var h = (hash || "").replace(/^#/, "");
    if (h.charAt(0) !== "/") return "";
    return h.split("?")[0].split("#")[0];
  }

  function esLaApp(pathname) {
    return pathname === "/" || pathname === "/index.html";
  }

  // URL que se le informa a GA para la carga de esta página.
  function urlDeCarga() {
    var l = window.location;
    var path = l.pathname;
    if (esLaApp(path)) {
      var ruta = rutaDelHash(l.hash);
      path = ruta && ruta !== "/" ? ruta : "/";
    }
    return l.origin + path + queryLimpia(l.search);
  }

  window.dataLayer = window.dataLayer || [];
  function gtag() { window.dataLayer.push(arguments); }
  window.gtag = window.gtag || gtag;

  // Última URL informada a GA: la de la carga y después la de cada ruta de la
  // app. Es el page_referrer del próximo page_view y el page_location de un
  // clic hecho adentro de la app.
  var ultimaUrl = urlDeCarga();

  window.gtag("js", new Date());
  // page_location explícito: se congela AHORA, con los UTM, aunque gtag.js
  // (asíncrono) termine de bajar cuando la app ya haya tocado la URL.
  window.gtag("config", MEASUREMENT_ID, { page_location: ultimaUrl });

  var s = document.createElement("script");
  s.async = true;
  s.src = "https://www.googletagmanager.com/gtag/js?id=" + MEASUREMENT_ID;
  (document.head || document.documentElement).appendChild(s);

  /*
   * page_view de un cambio de ruta de la app Flutter. `ruta` es la ruta de
   * GoRouter ("/home", "/clase/12"). Dart ya filtra la ruta inicial (la cubre
   * el page_view de `config`) y las repetidas; acá se re-chequea igual para
   * que nunca salgan dos seguidos de la misma URL.
   */
  function pageView(ruta, titulo) {
    try {
      if (!ruta || ruta.charAt(0) !== "/") return;
      var url = window.location.origin + ruta.split("?")[0].split("#")[0];
      if (url === ultimaUrl.split("?")[0]) return; // misma pantalla (con o sin UTM)
      var params = {
        page_location: url,
        page_referrer: ultimaUrl
      };
      if (titulo) params.page_title = titulo;
      ultimaUrl = url;
      window.gtag("event", "page_view", params);
    } catch (e) {}
  }

  /*
   * app_store_click. No bloquea ni demora la navegación: el hit sale por
   * sendBeacon (lo que GA4 usa por defecto), que sobrevive a que la página se
   * vaya. `alTerminar` es opcional y sólo lo usa el redirect automático de
   * /descargar: se llama cuando el hit salió o, si GA no responde, a los
   * `esperaMaxMs` — nunca se queda esperando.
   */
  function appStoreClick(linkUrl, linkText, placement, alTerminar, esperaMaxMs) {
    var hecho = false;
    function terminar() {
      if (hecho) return;
      hecho = true;
      if (typeof alTerminar === "function") alTerminar();
    }
    try {
      var params = {
        link_url: String(linkUrl || ""),
        link_text: String(linkText || "").replace(/\s+/g, " ").trim().slice(0, 100),
        placement: String(placement || "unknown"),
        page_location: esLaApp(window.location.pathname)
          ? ultimaUrl
          : window.location.origin + window.location.pathname + queryLimpia(window.location.search)
      };
      if (typeof alTerminar === "function") {
        params.event_callback = terminar;
        params.event_timeout = esperaMaxMs || 800;
      }
      window.gtag("event", "app_store_click", params);
    } catch (e) {}
    if (typeof alTerminar === "function") {
      // Respaldo si gtag.js ni siquiera cargó (bloqueador, red caída):
      // event_callback no se llamaría nunca.
      setTimeout(terminar, esperaMaxMs || 800);
    }
  }

  // Un único listener delegado para todos los <a> a la App Store de las
  // páginas estáticas. En captura para correr aunque otro handler corte la
  // propagación. Un clic = un evento: no hay handlers por botón que se sumen.
  document.addEventListener("click", function (ev) {
    try {
      var el = ev.target;
      while (el && el.nodeName !== "A") el = el.parentNode;
      if (!el || !el.href || el.href.indexOf("apps.apple.com") === -1) return;
      appStoreClick(
        el.href,
        el.getAttribute("data-link-text") || el.textContent,
        el.getAttribute("data-placement") || "unknown"
      );
    } catch (e) {}
  }, true);

  window.auraAnalytics = {
    measurementId: MEASUREMENT_ID,
    pageView: pageView,
    appStoreClick: appStoreClick
  };
})();
