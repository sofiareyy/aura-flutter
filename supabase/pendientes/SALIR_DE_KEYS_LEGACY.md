# Pendiente: migrar de la anon key legacy a la publishable

Fecha de la nota: 2026-08-21. Sale de la auditoría pre-build.
**Para DESPUÉS del build, con calma.** No es urgente y tocarlo apurado es riesgoso.

## Por qué

El proyecto ya tiene el sistema nuevo de API keys de Supabase conviviendo con
el viejo:

| Clave | Tipo | Estado |
|---|---|---|
| `anon` (`eyJ...`) | legacy JWT | en uso por la app |
| `service_role` (`eyJ...`) | legacy JWT | ya NO se usa (los crons pasaron a `sb_secret_`) |
| `sb_publishable_...` | publishable | sin usar |
| `sb_secret_...` | secret | la usan los crons y las edge functions |

Y las claves de firma:

| Clave | Alg | Estado |
|---|---|---|
| `94e6da74…` | HS256 | `previously_used` — es el `jwt_secret` clásico |
| `af58f973…` | ES256 | `in_use` |

La anon key legacy es un **JWT firmado con el HS256**. Mientras siga hardcodeada
en la app, ese secreto HS256 no se puede rotar ni deshabilitar.

## ⚠️ Lo que NO hay que hacer

**No rotar el `jwt_secret` / no deshabilitar las legacy keys** hasta terminar
esta migración. Si la anon key legacy deja de verificar:

- la app **1.0.6+24 que ya está publicada en la App Store** empieza a recibir
  401 en cada request — queda inutilizable para todos los usuarios de iOS
  hasta que Apple apruebe un build nuevo;
- la web se arregla redeployando, pero el móvil no;
- los triggers de push y de email al estudio dejan de autenticar.

Los crons **ya no dependen** del `jwt_secret` (usan `sb_secret_`, que no es un
JWT). Las edge functions tampoco: leen sus keys de variables de entorno que la
plataforma repunta sola.

## Los 3 lugares donde vive la anon key legacy

Verificado por hash contra la key real del proyecto (`sha256 = eb8e16a1...`):

1. **`lib/core/constants/app_constants.dart`** → `AppConstants.supabaseAnonKey`.
   Va compilada dentro del binario. Es la que obliga a un build nuevo.

2. **`public.notif_push_nueva()`** → variable `v_anon`, en el header
   `Authorization` / `apikey` del `net.http_post` a `push-enviar`.

3. **`public.notif_email_nueva_reserva()`** → ídem, hacia
   `nueva-reserva-estudio-email`.

En los casos 2 y 3 la anon key solo sirve para pasar el gateway; la autorización
real la da el `x-push-secret` / `x-notif-secret` que sale del Vault.

## Orden sugerido

1. Cambiar `supabaseAnonKey` por la `sb_publishable_...` y **probar bien**:
   login (email + Google + Apple), reserva, cancelación, compra de créditos.
   Es una constante, pero toca el arranque de la app: si la key no sirve, no
   arranca nada.
2. Actualizar el `v_anon` de las dos funciones de la base (se puede hacer antes
   que el punto 1: el gateway acepta ambas mientras las legacy estén
   habilitadas). Verificar que push y email siguen llegando.
3. Publicar el build con el punto 1 y **esperar a que la base instalada migre**.
   Mientras haya gente con la app vieja, la legacy tiene que seguir viva.
4. Recién ahí: deshabilitar las legacy keys y/o rotar el HS256.

## Comprobación rápida de dónde está la key

```bash
grep -rn "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" lib/
```

```sql
select p.proname
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and pg_get_functiondef(p.oid) like '%eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9%';
```
