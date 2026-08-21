# Pendiente (Dart): limpieza de la foto de perfil

Fecha de la nota: 2026-08-21. **Necesita build.** No urgente: la función YA
anda desde el fix de base (`supabase/FIX_FOTO_PERFIL_2026-08-21.sql`).

## Contexto

La foto de perfil nunca había funcionado: las dos pantallas suben al bucket
`avatares`, que no tenía policies. Se arregló del lado servidor el 2026-08-21 —
tres policies acotadas a la carpeta del propio usuario. **Con eso alcanza para
que ande**, sin tocar Dart.

Lo de abajo es calidad, no funcionalidad.

## 1. Dos implementaciones del mismo upload

| Pantalla | Cómo sube | Path |
|---|---|---|
| `editar_perfil_screen.dart` | `MediaUploadService.uploadAvatar()` | `{uid}/perfil.{ext}` |
| `mi_perfil_screen.dart:794` | upload directo, a mano | `{uid}/perfil.jpg` |

La segunda duplica la lógica en vez de usar el service, y ya divergió: fuerza
`.jpg` y `contentType: image/jpeg`, la otra respeta la extensión del archivo
elegido.

**Qué hacer:** que `mi_perfil_screen` use `MediaUploadService.uploadAvatar()`.
Borra ~20 líneas y deja un solo camino.

## 2. El `catch` genérico se traga la causa

Las dos muestran *"No se pudo subir la imagen. Revisá Storage y volvé a
intentarlo."* y descartan el error real. **Es lo que escondió este bug**: si
hubiera mostrado `violates row-level security policy`, se resolvía en minutos.

Mismo patrón que escondió los dos bugs de columna de `delete-account`.

**Qué hacer:** loguear el error real (`debugPrint` / Sentry) y, si es un
`StorageException`, mostrar algo accionable. No hace falta exponerle el detalle
técnico a la usuaria, pero sí que quede en los logs.

## 3. Extensión variable deja archivos huérfanos

`uploadAvatar` usa la extensión del archivo elegido. Si subís `.png` y después
`.jpg`, quedan **dos** archivos (`perfil.png` y `perfil.jpg`) y `avatar_url`
apunta al último. El viejo queda ocupando espacio para siempre (no hay policy
de DELETE, a propósito).

**Qué hacer:** normalizar a `.jpg` siempre, como ya hace `mi_perfil_screen`.
Así el upsert pisa el mismo archivo y nunca hay huérfanos.

## 4. Dos buckets para lo mismo

- `avatares` — el que usan las dos pantallas. Path `{uid}/perfil.{ext}`.
- `user-media/avatars/{uid}/{ts}.{ext}` — de una versión anterior. Tiene **1**
  archivo, de `clic@aura.com`.

**Qué hacer:** decidir uno. Si se elige `avatares`, migrar ese único archivo y
quitarle a `user-media` la carpeta `avatars/` de la policy. Si se elige
`user-media`, apuntar las dos pantallas ahí (path `avatars/{uid}/...`, ojo que
el uid pasa a ser el segmento **2**) y borrar el bucket `avatares`.

Preferible `avatares`: es lo que el código ya usa y no requiere tocar paths.

## Verificación cuando se haga

Con la app corriendo, no por SQL:

1. Subir foto desde **Mi Perfil** → se ve, y `usuarios.avatar_url` queda seteado.
2. Subir foto desde **Perfil → Configuración → Editar perfil** → ídem.
3. **Cambiar** la foto dos veces seguidas → la segunda también anda (es la que
   fallaba sin la policy de UPDATE).
4. Intentar un archivo > 10 MB → lo rechaza el gateway de Storage.
5. Intentar un PDF → rechazado por `allowed_mime_types = image/*`.

Las 4 y 5 no se pueden probar por SQL: las aplica el gateway, no la policy.
