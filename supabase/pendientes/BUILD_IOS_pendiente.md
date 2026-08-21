# Registro de builds de iOS

Última actualización: 2026-08-21.

## Historial de versiones publicadas

| Versión | Qué llevó | Estado |
|---------|-----------|--------|
| `1.0.5+21` | Precios nuevos de packs y planes, precio decidido en el servidor (`c8c7497`) | compilado; no se pudo confirmar si se subió |
| `1.0.6+23` | Se compiló el 2026-08-14 con los precios. **No quedó registrado si se subió** — por eso se saltó al 24 | ⚠️ número consumido |
| `1.0.6+24` | Precios + los 5 fixes de Dart de abajo + `MinimumOSVersion 15` | subido a App Store Connect el 2026-08-18 ✅ |
| **`1.0.6+25`** | Push (FCM) en Android e iOS · force-update · modo visita · lista de espera · fixes de seguridad de base | 🔨 **en preparación** — número reservado el 2026-08-21 |

### Notas del 1.0.6+25 (2026-08-21)

- Se mantiene la versión visible `1.0.6`: los cambios son por atrás (push,
  force-update, seguridad de base), no hay features nuevas de cara al usuario.
- **Push iOS**: `GoogleService-Info.plist` agregado al target Runner y a Copy
  Bundle Resources (`dbfb2f0`). Verificado que viaja dentro del `.app`.
  El App ID `app.somosaura.aura` ya tiene la capability Push habilitada —
  confirmado leyendo el provisioning profile de desarrollo, que trae
  `aps-environment`.
- **Push Android**: `google-services.json` en `android/app/`. AAB de release
  compilado y firmado con `aura-upload`; la huella coincide con la publicada en
  `web/.well-known/assetlinks.json`.
- ⚠️ El **perfil de App Store** (`iOS Team Store Provisioning Profile`) es del
  18/08 y **no** trae `aps-environment`. Xcode lo regenera solo al archivar con
  firma automática. Si el archive falla por provisioning, es por esto.
- ⚠️ Los dos archivos de Firebase están gitignoreados: hay que copiarlos a mano
  en cada máquina donde se compile.

> Regla para la próxima: commitear `pubspec.yaml` **junto con** el build que se
> sube. El lío del 23 fue exactamente esto — el número se consumió en un binario
> pero el repo nunca lo registró, así que después no había forma de saber si ese
> número estaba quemado o libre.

## Salió en 1.0.6+24 — los 5 fixes de Dart

| # | Fix | Archivo | Qué arregla en la app |
|---|-----|---------|-----------------------|
| 1 | Filtrar columnas al editar un horario fijo | `services/estudio_admin_service.dart` (`actualizarHorarioFijo`) | Editar un horario fijo no guardaba **nada**: el payload mandaba `tipo`, que no existe en `horarios_fijos`, y PostgREST rechazaba el PATCH entero (`PGRST204`) |
| 2 | Cartel de error accionable al guardar horario/clase | `screens/clases/mis_clases_screen.dart` | Mostraba el `PostgrestException` crudo, y ponía `_tablaOk = false` reemplazando toda la lista por un panel de error equivocado |
| 3 | Filtros de fecha descartados | `services/estudio_admin_service.dart` (`getClasesDeEstudio`) | Los filtros de postgrest no mutan el builder. `from`/`to` se perdían → la pantalla de asistencia/QR traía las clases **más viejas** y decía "Sin clase activa ahora" con el estudio lleno de clases. También hacía que el backoffice trajera todas las clases sin recortar |
| 4 | `user_id` en vez de `usuario_id` | `screens/home/home_screen.dart` | La consulta a `creditos_movimientos` daba `42703`, caía en el catch y el usuario nuevo nunca veía el estado de bienvenida |
| 5 | Códigos de error de reserva + `ReservaException` | `services/reservas_service.dart`, `screens/reservas/confirmar_reserva_screen.dart` | `ya_reservada`, `reserva_cerrada`, `sin_creditos` y `no_auth` caían al cartel genérico. Además había doble traducción: la pantalla re-adivinaba por substring sobre un mensaje ya traducido |

Todos estos ya estaban en `main` y vivos en la web desde el 2026-08-18, y
ahora también viajan en la app nativa a partir del build 24.

## Ya resuelto server-side — NO necesita build

Estos salieron en la base y valen para web y app al instante, en cualquier
versión instalada:

- **FK `clases` → `estudios`** (`clases_estudio_id_fkey`, sin CASCADE). Sin
  ella, el embed `estudios(...)` daba `400 PGRST200` y **ninguna reserva podía
  crearse** desde el 2026-07-20.
- **`extensions.digest` en `reservar_clase`.** pgcrypto vive en el schema
  `extensions`; con `search_path=public` tiraba `42883` y la reserva nunca
  generaba el código QR.
- **`tipo_precio` en `generar_clases_estudio`.** Leía un campo que no existe en
  `horarios_fijos` (`42703`), así que la RPC rápida fallaba siempre y el
  backoffice caía a un loop cliente de ~600 llamadas por carga.
- **`estudio_id` ambiguo en `list_my_studios`** (`42702`). Rompía el selector
  de estudios de los admins multi-estudio.

## Todavía sin resolver

- **Lista de espera:** `lista_espera.posicion` no existe y el cliente la pide
  (`reservas_service.dart`, `getListaEspera`). La pantalla está rota.

  **DECIDIDO (2026-08-18): se calcula el puesto por `created_at`, NO se agrega
  la columna `posicion`.** Es más barato y no se puede desincronizar: la
  posición sale del orden de llegada dentro de cada `clase_id`, así que no hay
  que renumerar a nadie cuando alguien se baja de la lista.

  Al implementarlo: sacar `posicion` del `.select()` del cliente y derivar el
  puesto con un `row_number() over (partition by clase_id order by created_at)`
  —vía vista o RPC— o bien calcularlo en Dart sobre la lista ya ordenada.
- **Créditos de bienvenida:** los RPC no existen. Es a propósito — ver
  `supabase/pendiente_bienvenida/LEEME.md`. No tocar el toggle de Admin → Config
  hasta aplicar esa migración.
- **Estudio activo como puntero legacy:** las RLS y `getCurrentStudioId()`
  cuelgan de `usuarios.estudio_id` en vez de `estudio_admins`, y
  `usuarios.rol` se reescribe en cada cambio de estudio. Tema grande, aparte.
