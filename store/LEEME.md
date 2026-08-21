# Material para las tiendas

Assets de la ficha de Google Play y App Store. **No se empaquetan en la app**:
`pubspec.yaml` solo declara `assets/images/`, así que esta carpeta no suma peso
al build.

## `play/icon-512.png`

Ícono de la ficha de Google Play. 512×512, PNG de 8 bits por canal, sin canal
alfa, 20 KB.

Generado el 2026-08-21 desde
`ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png`
con:

```bash
sips -z 512 512 ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png \
     --out store/play/icon-512.png
```

### Por qué NO se usó `web/icons/Icon-512.png`

Ya mide 512×512, pero tiene **esquinas redondeadas y transparencia**. Google
Play aplica su propia máscara redondeada sobre el ícono, así que uno
pre-redondeado queda doblemente recortado y las esquinas transparentes se ven
mal. El de iOS es cuadrado completo y opaco, que es lo que Play espera.

### Si cambia el logo

Regenerar desde el de iOS con el mismo comando. Mantener: 512×512 exacto,
cuadrado completo (sin redondear a mano), menos de 1 MB.

## `play/feature-graphic-1024x500.png`

Gráfico de funciones de la ficha de Google Play. 1024×500, PNG opaco, 47 KB.

Generado el 2026-08-21 con `play/generar-feature-graphic.py` (necesita Pillow).
Se puede regenerar en un entorno aislado, sin instalar nada en el sistema:

```bash
python3 -m venv /tmp/venv && /tmp/venv/bin/pip install Pillow
/tmp/venv/bin/python store/play/generar-feature-graphic.py
```

### Decisiones de diseño

- Colores de marca tomados de las páginas web: fondo `#0D0D0D`, naranja
  `#E8763A`, crema `#F5F0E8`.
- Tipografía **Avenir Next** (del sistema). La web usa DM Sans, que no está
  instalada; Avenir Next es la más cercana en carácter (geométrica humanista).
- El wordmark lleva tracking amplio y punto naranja, replicando el `AURA.` de
  las plantillas de mail (`letter-spacing: 4px` sobre 28px ≈ 0.14em).
- Bajada y claim salen de textos reales del proyecto: la descripción de
  `web/descargar/index.html` y el `Mové. Explorá. Viví.` de los mails.
- Sin transparencia: Play exige el gráfico de funciones opaco.
- Todo el contenido queda dentro del área segura (Play puede recortar los
  bordes y superponer un botón de play si hay video).

### Si cambia el logo o el claim

Editar el script y volver a correrlo. Mantener 1024×500 exacto y opaco.
