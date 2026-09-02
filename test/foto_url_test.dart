import 'package:aura_app/utils/foto_url.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fotos livianas por el endpoint de transformación de Storage.
void main() {
  const base = 'https://hvgqpzvornlnxmsbqnwg.supabase.co/storage/v1';
  const publica = '$base/object/public/study-media/class-media/x/1.png';

  test('reescribe el objeto público al endpoint de transformación', () {
    expect(
      fotoOptimizada(publica, ancho: 400),
      '$base/render/image/public/study-media/class-media/x/1.png'
      '?width=400&quality=74',
    );
  });

  test('respeta el ancho y la calidad que le pidan', () {
    expect(fotoOptimizada(publica, ancho: 900), contains('width=900'));
    expect(
      fotoOptimizada(publica, ancho: 900, calidad: 60),
      contains('quality=60'),
    );
  });

  test('no toca lo que no es una foto pública de este Storage', () {
    // Foto de Google del login social.
    const google = 'https://lh3.googleusercontent.com/a/AAcHT.jpg';
    expect(fotoOptimizada(google, ancho: 400), google);
    expect(fotoOptimizada(null, ancho: 400), isNull);
    expect(fotoOptimizada('', ancho: 400), '');
  });

  test('no vuelve a transformar una URL que ya trae query', () {
    // El avatar lleva `?t=` de cache-buster: agregarle ?width= lo rompería.
    const conQuery = '$publica?t=123';
    expect(fotoOptimizada(conQuery, ancho: 400), conQuery);
    final yaTransformada = fotoOptimizada(publica, ancho: 400)!;
    expect(fotoOptimizada(yaTransformada, ancho: 400), yaTransformada);
  });

  test('la cabecera pide webp: sin ella el endpoint devuelve el png entero', () {
    // Medido el 2/9/2026 sobre una foto de 2,4 MB: con Accept webp la misma
    // foto a width=400 pesa 94 KB; sin la cabecera, 968 KB.
    expect(headersFoto['Accept'], contains('image/webp'));
  });
}
