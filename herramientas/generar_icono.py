"""Genera el icono maestro de Aura con bordes suaves.

El diseño es EXACTO al que ya estaba (medido del PNG original):
  · fondo         #E8763A
  · anillo negro  #1A1A1A, radio exterior 27,05% del lienzo, grosor 6,93%
  · punto central #1A1A1A, radio 8,01%

Lo unico que cambia es la calidad del borde: se dibuja a 4x y se promedia
(supersampling), que es lo que produce el antialiasing real. El original tenia
exactamente 2 colores -sin un solo pixel de transicion- y por eso las curvas se
veian escalonadas.
"""
import struct, zlib, sys

NARANJA = (0xE8, 0x76, 0x3A)
NEGRO   = (0x1A, 0x1A, 0x1A)
R_EXT, GROSOR, R_PUNTO = 277/1024, 71/1024, 82/1024

def png(w, h, pixels, alfa=False):
    ct = 6 if alfa else 2
    bpp = 4 if alfa else 3
    raw = b''.join(b'\x00' + bytes(pixels[y*w*bpp:(y+1)*w*bpp]) for y in range(h))
    def chunk(t, d):
        c = t + d
        return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    ihdr = struct.pack('>IIBBBBB', w, h, 8, ct, 0, 0, 0)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr)
            + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))

def cobertura(cx, cy, x, y, ss):
    """Cuanta tinta cae en el pixel (x,y), muestreando ss x ss puntos."""
    r_ext = R_EXT * TAM; r_int = r_ext - GROSOR * TAM; r_pto = R_PUNTO * TAM
    dentro = 0
    for sy in range(ss):
        for sx in range(ss):
            px = x + (sx + 0.5) / ss - cx
            py = y + (sy + 0.5) / ss - cy
            d = (px*px + py*py) ** 0.5
            if (r_int <= d <= r_ext) or (d <= r_pto):
                dentro += 1
    return dentro / (ss * ss)

def generar(tam, ss=4, fondo=NARANJA, solo_capa=False):
    global TAM
    TAM = tam
    c = tam / 2
    out = bytearray()
    bpp = 4 if solo_capa else 3
    for y in range(tam):
        for x in range(tam):
            a = cobertura(c, c, x, y, ss)
            if solo_capa:
                out += bytes(NEGRO) + bytes([round(a * 255)])
            else:
                out += bytes(round(fondo[i] * (1 - a) + NEGRO[i] * a) for i in range(3))
    return bytes(out)

if __name__ == '__main__':
    tam = int(sys.argv[1]); dest = sys.argv[2]
    capa = len(sys.argv) > 3 and sys.argv[3] == 'capa'
    if capa:
        # La capa de primer plano del icono adaptativo de Android.
        #
        # El tamaño NO se reduce acá: `flutter_launcher_icons` ya aplica un
        # `inset` del 16% en el XML, y Android recorta con su máscara ~el 28%
        # exterior. Con el anillo a su tamaño normal (54% de diámetro), tras el
        # inset queda en 37% del lienzo, cómodo dentro de la zona segura y del
        # mismo tamaño relativo que se ve en iOS. Reducirlo también acá lo
        # dejaba diminuto.
        c = tam / 2
        r_ext, r_int, r_pto = R_EXT * tam, (R_EXT - GROSOR) * tam, R_PUNTO * tam
        out = bytearray()
        for y in range(tam):
            for x in range(tam):
                dentro = 0
                for sy in range(4):
                    for sx in range(4):
                        qx = x + (sx + .5) / 4 - c
                        qy = y + (sy + .5) / 4 - c
                        d = (qx * qx + qy * qy) ** .5
                        if (r_int <= d <= r_ext) or (d <= r_pto):
                            dentro += 1
                out += bytes(NEGRO) + bytes([round(dentro / 16 * 255)])
        open(dest, 'wb').write(png(tam, tam, out, alfa=True))
    else:
        open(dest, 'wb').write(png(tam, tam, generar(tam)))
    print(f'  {dest}  {tam}x{tam}')
