/// Fotos livianas: pedirle a Storage la medida que la tarjeta necesita.
///
/// El problema medido el 2/9/2026 sobre las 102 fotos de `study-media`:
/// pesan 1,17 MB en promedio y la más pesada 6,4 MB. Los .jpg que sube la app
/// del iPhone están bien (366 KB de promedio, `image_picker` los reescala),
/// pero los .png pesan 2,2 MB y los .avif 4,1 MB: el reescalado del navegador
/// re-encodea en el formato ORIGINAL, y `canvas.toBlob` ignora la calidad si
/// no es jpeg o webp. Una tarjeta que muestra la foto a 186 px se estaba
/// bajando 2,4 MB.
///
/// Supabase Storage sirve cualquier objeto público también por
/// `/render/image/public/`, que lo reescala y —si el cliente dice que acepta
/// webp— lo devuelve en webp. Medido contra la foto de perfil de un estudio:
///
///   original .png .............. 2.407.868 bytes
///   width=400 (png) ..............  968.299 bytes
///   width=400 + Accept webp ......   94.334 bytes   ← 25× más liviana
///
/// De yapa arregla los formatos que Flutter no sabe decodificar: un .avif de
/// 4,5 MB y un .heic salen del endpoint como webp de 30 y 75 KB. Hoy esas
/// fotos se ven como el degradado de fallback.
///
/// ⚠️ `resize=contain` NO es opcional. Sin él, Supabase entiende `width=400`
/// como "una caja de 400 de ancho por el ALTO ORIGINAL" y, como el modo por
/// defecto es `cover`, **recorta los costados en vez de achicar la foto**. Se
/// escapó en el push del 2/9 y estuvo unas horas en producción: las tarjetas
/// recibían la foto ya recortada y encima le aplicaban su propio `BoxFit.cover`
/// — doble recorte. Medido sobre una foto de 1600 × 1067:
///
///   width=900 .................... 900 × 1067  (0,843 — recortada) · 80 KB
///   width=900&resize=contain ..... 900 ×  600  (1,500 — entera)    · 53 KB
///
/// Con `contain` la foto llega entera Y más liviana. `foto_url_test.dart` lo
/// fija para que no se vuelva a caer.
///
/// ⚠️ La organización está en plan **free** y Supabase documenta las
/// transformaciones como feature de Pro. Al 2/9/2026 el endpoint responde 200
/// (medido), pero por si eso cambia cada foto tiene su red: si la versión
/// optimizada falla, el widget reintenta la URL original. Y [fotosOptimizadas]
/// apaga todo desde un solo lugar.
library;

/// Interruptor único. En false, [fotoOptimizada] devuelve la URL tal cual y la
/// app queda exactamente como antes de este cambio.
const bool fotosOptimizadas = true;

const String _segmentoPublico = '/storage/v1/object/public/';
const String _segmentoRender = '/storage/v1/render/image/public/';

/// Cabecera que hace que Storage devuelva webp en vez del formato original.
/// Sin esto el endpoint reescala pero mantiene el png (968 KB contra 94 KB).
const Map<String, String> headersFoto = {'Accept': 'image/webp,image/*,*/*'};

/// La misma foto pedida a [ancho] píxeles de ancho.
///
/// [ancho] es el ancho REAL de descarga, no el del hueco en pantalla: conviene
/// pedir ~2× el hueco para que se vea nítida en pantallas retina.
///
/// Devuelve [url] sin tocar si es null, si está vacía, si no es un objeto
/// público de este Storage (por ejemplo una foto de Google del login social) o
/// si [fotosOptimizadas] está en false.
String? fotoOptimizada(String? url, {required int ancho, int calidad = 74}) {
  if (url == null || url.isEmpty) return url;
  if (!fotosOptimizadas) return url;
  if (!url.contains(_segmentoPublico)) return url;
  // Una URL ya transformada (o con query propia, como el cache-buster del
  // avatar) no se vuelve a tocar: se le agregarían dos veces los parámetros.
  if (url.contains(_segmentoRender) || url.contains('?')) return url;
  return '${url.replaceFirst(_segmentoPublico, _segmentoRender)}'
      '?width=$ancho&resize=contain&quality=$calidad';
}
