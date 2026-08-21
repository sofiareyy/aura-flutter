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
