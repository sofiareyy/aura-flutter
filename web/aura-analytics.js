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

  // Navegador de una cuenta interna o de prueba (5/11/2026): la app lo marca
  // cuando esa cuenta inicia sesión, y desde ahí este navegador no le manda
  // NADA a GA4 —tampoco page_view—, aunque después cierre sesión.
  // `ga-disable-<ID>` es el apagado oficial de gtag.js.
  var INTERNA_STORAGE = "aura_interna";
  function esInterna() {
    try { return window.localStorage.getItem(INTERNA_STORAGE) === "1"; } catch (e) { return false; }
  }
  if (esInterna()) window["ga-disable-" + MEASUREMENT_ID] = true;

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

  /*
   * CLIC DE META (fbclid), 29/10/2026.
   *
   * Meta le agrega ?fbclid=... a cada clic de un anuncio. Si no se guarda en
   * ESA carga, ese clic no se puede atribuir nunca más: GoRouter y los
   * redirects lo sacan de la URL. Se guarda con el formato y la cookie
   * estándar de Meta (_fbc = "fb.1.<ms del clic>.<fbclid>", 90 días), así el
   * píxel —si algún día se instala— lo reconoce solo, y la app lo manda a la
   * base apenas hay sesión (lib/services/analytics/atribucion_meta.dart) para
   * los eventos de servidor (API de Conversiones).
   *
   * Con hash routing Meta puede pegar el fbclid antes o después del '#'
   * (somosaurapass.com/?fbclid=X#/landing o .../#/landing?fbclid=X): se
   * buscan los dos. Un clic nuevo reemplaza al anterior; recargar la misma
   * URL no le cambia la fecha.
   */
  var FBC_COOKIE = "_fbc";
  var FBC_STORAGE = "aura_fbc";
  var FBC_DIAS = 90;

  function fbclidDeLaUrl() {
    var l = window.location;
    var fuentes = [l.search];
    var h = l.hash || "";
    var q = h.indexOf("?");
    if (q !== -1) fuentes.push(h.slice(q));
    for (var i = 0; i < fuentes.length; i++) {
      try {
        var v = new URLSearchParams(fuentes[i] || "").get("fbclid");
        if (v && /^[A-Za-z0-9_\-]{10,500}$/.test(v)) return v;
      } catch (e) {}
    }
    return null;
  }

  function fbcValido(v) {
    return typeof v === "string" && /^fb\.1\.\d{13}\.[A-Za-z0-9_\-]{10,500}$/.test(v);
  }

  function leerFbc() {
    try {
      var m = document.cookie.match(/(?:^|;\s*)_fbc=([^;]+)/);
      if (m && fbcValido(decodeURIComponent(m[1]))) return decodeURIComponent(m[1]);
    } catch (e) {}
    try {
      var s = window.localStorage.getItem(FBC_STORAGE);
      if (fbcValido(s)) return s;
    } catch (e) {}
    return null;
  }

  function guardarFbc(fbc) {
    try {
      document.cookie =
        FBC_COOKIE + "=" + encodeURIComponent(fbc) +
        "; max-age=" + FBC_DIAS * 86400 +
        "; path=/; SameSite=Lax" +
        (window.location.protocol === "https:" ? "; Secure" : "");
    } catch (e) {}
    // Respaldo por si la cookie no se pudo escribir.
    try { window.localStorage.setItem(FBC_STORAGE, fbc); } catch (e) {}
  }

  try {
    var fbclid = fbclidDeLaUrl();
    if (fbclid) {
      var actual = leerFbc();
      if (!actual || actual.split(".").slice(3).join(".") !== fbclid) {
        guardarFbc("fb.1." + Date.now() + "." + fbclid);
      }
    }
  } catch (e) {}

  /*
   * EMBUDO (5/11/2026): de la landing a la compra.
   *
   * La campaña con la que llegó la persona (utm_source, utm_medium,
   * utm_campaign, utm_content, fbclid) se guarda al cargar, 30 días, y viaja
   * en cada evento del embudo. Una llegada con campaña nueva reemplaza a la
   * anterior; una sin campaña no la borra. Se buscan antes y después del '#'.
   *
   * Nunca se manda un mail, un nombre ni un teléfono: el usuario va como su
   * número interno de cuenta (user_id), que no dice quién es.
   */
  var ATRIB_STORAGE = "aura_atribucion";
  var ATRIB_DIAS = 30;
  var ATRIB_CAMPOS = ["utm_source", "utm_medium", "utm_campaign", "utm_content", "fbclid"];

  function atribucionDeLaUrl() {
    var l = window.location;
    var fuentes = [l.search];
    var h = l.hash || "";
    var q = h.indexOf("?");
    if (q !== -1) fuentes.push(h.slice(q));
    var out = {};
    var hay = false;
    for (var i = 0; i < fuentes.length; i++) {
      try {
        var sp = new URLSearchParams(fuentes[i] || "");
        for (var j = 0; j < ATRIB_CAMPOS.length; j++) {
          var v = sp.get(ATRIB_CAMPOS[j]);
          if (v) { out[ATRIB_CAMPOS[j]] = String(v).slice(0, 100); hay = true; }
        }
      } catch (e) {}
    }
    return hay ? out : null;
  }

  function atribucion() {
    try {
      var raw = window.localStorage.getItem(ATRIB_STORAGE);
      if (!raw) return {};
      var a = JSON.parse(raw);
      if (!a || typeof a !== "object" || !a.t || Date.now() - a.t > ATRIB_DIAS * 86400000) return {};
      var out = {};
      for (var i = 0; i < ATRIB_CAMPOS.length; i++) {
        if (a[ATRIB_CAMPOS[i]]) out[ATRIB_CAMPOS[i]] = String(a[ATRIB_CAMPOS[i]]);
      }
      return out;
    } catch (e) { return {}; }
  }

  try {
    var nueva = atribucionDeLaUrl();
    if (nueva) {
      nueva.t = Date.now();
      window.localStorage.setItem(ATRIB_STORAGE, JSON.stringify(nueva));
    }
  } catch (e) {}

  var usuarioId = null;

  /** Evento del embudo. `params` es un objeto JS plano (o un JSON en texto). */
  function evento(nombre, params) {
    try {
      if (esInterna() || !nombre) return;
      var p = {};
      if (typeof params === "string") { try { p = JSON.parse(params) || {}; } catch (e) { p = {}; } }
      else if (params && typeof params === "object") p = params;
      var a = atribucion();
      for (var k in a) if (Object.prototype.hasOwnProperty.call(a, k)) p[k] = a[k];
      if (usuarioId) p.user_id = usuarioId;
      p.page_location = esLaApp(window.location.pathname) ? ultimaUrl : window.location.href.split("?")[0];
      window.gtag("event", String(nombre), p);
    } catch (e) {}
  }

  /** La cuenta con sesión (su id interno), o null al cerrar sesión. */
  function usuario(id) {
    try {
      usuarioId = id ? String(id) : null;
      window.gtag("set", { user_id: usuarioId });
    } catch (e) {}
  }

  /** Esta cuenta es interna: este navegador deja de medir, para siempre. */
  function marcarInterna() {
    try { window.localStorage.setItem(INTERNA_STORAGE, "1"); } catch (e) {}
    window["ga-disable-" + MEASUREMENT_ID] = true;
  }

  /*
   * Lo que el checkout guarda en el pago para que la compra (que la confirma
   * Mercado Pago al servidor, sin navegador) se una a esta visita en GA4:
   *  · client_id: el navegador, sacado de la cookie _ga ("GA1.1.<a>.<b>" → "<a>.<b>").
   *  · session_id: la visita, de la cookie _ga_<ID> (formatos GS1 y GS2).
   *  · la campaña guardada.
   * En texto JSON para que el puente de Dart sea simple.
   */
  function leerCookie(nombre) {
    try {
      var m = document.cookie.match(new RegExp("(?:^|;\\s*)" + nombre + "=([^;]+)"));
      return m ? decodeURIComponent(m[1]) : null;
    } catch (e) { return null; }
  }

  function clientId() {
    var c = leerCookie("_ga");
    var m = c && c.match(/^GA\d\.\d\.(\d+\.\d+)$/);
    return m ? m[1] : null;
  }

  function sessionId() {
    var c = leerCookie("_ga_" + MEASUREMENT_ID.replace(/^G-/, ""));
    if (!c) return null;
    var m = c.match(/^GS2\.\d\.s(\d+)/) || c.match(/^GS1\.\d\.(\d+)\./);
    return m ? m[1] : null;
  }

  function datosCheckout() {
    try {
      if (esInterna()) return "{}";
      return JSON.stringify({ client_id: clientId(), session_id: sessionId(), atribucion: atribucion() });
    } catch (e) { return "{}"; }
  }

  window.auraAnalytics = {
    evento: evento,
    usuario: usuario,
    marcarInterna: marcarInterna,
    datosCheckout: datosCheckout,
    measurementId: MEASUREMENT_ID,
    pageView: pageView,
    appStoreClick: appStoreClick,
    // El clic de Meta guardado ("fb.1.<ms>.<fbclid>") o null.
    fbc: leerFbc
  };
})();
