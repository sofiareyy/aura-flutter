# Pendiente para el próximo build de iOS

Todo esto **ya está en `main` y vivo en la web** (GitHub Pages deploya solo al
pushear). Lo que falta es que salga en la **app nativa**, que necesita build y
revisión de Apple. Hasta entonces, en iOS/Android estos bugs siguen presentes.

Última actualización: 2026-08-18.

## Se acumula para el build

| # | Fix | Archivo | Qué arregla en la app |
|---|-----|---------|-----------------------|
| 1 | Filtrar columnas al editar un horario fijo | `services/estudio_admin_service.dart` (`actualizarHorarioFijo`) | Editar un horario fijo no guardaba **nada**: el payload mandaba `tipo`, que no existe en `horarios_fijos`, y PostgREST rechazaba el PATCH entero (`PGRST204`) |
| 2 | Cartel de error accionable al guardar horario/clase | `screens/clases/mis_clases_screen.dart` | Mostraba el `PostgrestException` crudo, y ponía `_tablaOk = false` reemplazando toda la lista por un panel de error equivocado |
| 3 | Filtros de fecha descartados | `services/estudio_admin_service.dart` (`getClasesDeEstudio`) | Los filtros de postgrest no mutan el builder. `from`/`to` se perdían → la pantalla de asistencia/QR traía las clases **más viejas** y decía "Sin clase activa ahora" con el estudio lleno de clases. También hacía que el backoffice trajera todas las clases sin recortar |
| 4 | `user_id` en vez de `usuario_id` | `screens/home/home_screen.dart` | La consulta a `creditos_movimientos` daba `42703`, caía en el catch y el usuario nuevo nunca veía el estado de bienvenida |
| 5 | Códigos de error de reserva + `ReservaException` | `services/reservas_service.dart`, `screens/reservas/confirmar_reserva_screen.dart` | `ya_reservada`, `reserva_cerrada`, `sin_creditos` y `no_auth` caían al cartel genérico. Además había doble traducción: la pantalla re-adivinaba por substring sobre un mensaje ya traducido |

## Ya resuelto server-side — NO necesita build

Estos salieron en la base y valen para web y app al instante:

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
  (`reservas_service.dart`, `getListaEspera`). La pantalla está rota. Hay que
  decidir si se agrega la columna o se calcula el puesto por `created_at`.
- **Créditos de bienvenida:** los RPC no existen. Es a propósito — ver
  `supabase/pendiente_bienvenida/LEEME.md`. No tocar el toggle de Admin → Config
  hasta aplicar esa migración.
- **Estudio activo como puntero legacy:** las RLS y `getCurrentStudioId()`
  cuelgan de `usuarios.estudio_id` en vez de `estudio_admins`, y
  `usuarios.rol` se reescribe en cada cambio de estudio. Tema grande, aparte.
