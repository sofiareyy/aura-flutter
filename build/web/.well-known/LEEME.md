# assetlinks.json — App Links de Android

Este archivo se sirve en `https://somosaurapass.com/.well-known/assetlinks.json`
(GitHub Pages lo publica solo al pushear a `main`). Es lo que hace que un link
`https://somosaurapass.com/payment-result?...` abra la app en vez del navegador.

## ⚠️ Falta un fingerprint — se completa después de la primera subida a Play

Hoy el archivo declara **una sola** huella: la de la **clave de subida**
(`/Users/reyfer/keys/aura-upload.jks`, alias `aura-upload`).

Con **Play App Signing** activado, los APKs que instala la gente **no** están
firmados con esa clave: Google los re-firma con su propia *app signing key*.
Android verifica contra la firma del APK instalado, así que **mientras falte la
huella de Google, los App Links no van a verificar para nadie que instale desde
Play**.

No es un bug nuevo: antes el archivo tenía el texto
`REEMPLAZAR_CON_SHA256_DEL_KEYSTORE`, o sea que nunca verificó. Ahora al menos
es válido para builds instalados a mano.

**Impacto acotado:** los flujos críticos (volver de Mercado Pago, callback de
OAuth, reset de contraseña) usan el scheme propio `aura://`, que **no** requiere
verificación y funciona igual. Lo único que no anda es abrir la app desde un
link `https://`.

### Cómo completarlo

1. Subí el primer AAB a Play y activá Play App Signing.
2. Play Console → **Test and release** → **App integrity** → **App signing key
   certificate** → copiá el **SHA-256**.
3. Agregalo al array, **sin borrar el de subida** (Google recomienda dejar los
   dos: así los links también funcionan en los builds internos firmados con la
   clave de subida):

```json
"sha256_cert_fingerprints": [
  "1A:70:15:2B:...:89",     ← clave de subida (la de este repo)
  "XX:XX:XX:...",           ← app signing key de Google, de Play Console
]
```

4. Pusheá a `main` (GitHub Pages redeploya solo) y verificá:

```bash
curl -s https://somosaurapass.com/.well-known/assetlinks.json
adb shell pm verify-app-links --re-verify app.somosaura.aura
adb shell pm get-app-links app.somosaura.aura   # tiene que decir "verified"
```

## Datos de referencia

| | |
|---|---|
| `package_name` | `app.somosaura.aura` (igual al bundle de iOS) |
| Clave de subida | `/Users/reyfer/keys/aura-upload.jks`, alias `aura-upload` |
| SHA-256 de subida | `1A:70:15:2B:1E:A2:08:C3:44:4F:91:56:47:83:E4:B8:D3:14:20:4A:FD:69:73:97:01:8B:2E:FB:D5:12:13:89` |

Si algún día cambia el `applicationId` o la clave de firma, **este archivo hay
que actualizarlo** o los App Links dejan de verificar en silencio.

> El dominio viejo `somosauraar.netlify.app` sigue online y sirviendo un
> `assetlinks.json` con el placeholder. Ya no está en el `AndroidManifest.xml`,
> así que no afecta — pero conviene darlo de baja para que no confunda.
