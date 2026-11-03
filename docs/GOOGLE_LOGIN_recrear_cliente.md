# Login con Google: qué hacer si Google borra el cliente OAuth

Escrito el 3/11/2026, cuando Google avisó que iba a borrar el cliente por
"inactivo" aunque ese mes 32 personas habían entrado con Google.

## Qué hay hoy

| | |
|---|---|
| Proyecto de Google Cloud | **somosaura-app** (número 936237490385) |
| Cliente OAuth | **Aura Web**, tipo "Aplicación web", creado el 20/4/2026 |
| Client ID | `936237490385-ejqufo640ou9krrjo8rcep6abm1cla79.apps.googleusercontent.com` |
| Dónde está cargado | Supabase → Authentication → Sign In / Providers → **Google** |

- Es el **único** cliente. La app de iPhone, la de Android y la web usan este
  mismo: el botón "Continuar con Google" abre el navegador y el login lo
  resuelve Supabase. La app no tiene client IDs propios, así que **recrearlo no
  necesita un build nuevo**.
- **No confundir** con el proyecto **somosaurapass** de Firebase (número
  239430835522): ese es el de las notificaciones push y no tiene nada que ver
  con el login.
- El **client secret NO va en este archivo** (el repo es público). Vive solo en
  Supabase y en la consola de Google.

## Cómo me entero de que se rompió

El resumen diario trae la línea **"Último ingreso con Google: hace X días"**.
Hay unos 7 ingresos con Google por semana: si pasa de 7 días se pone en rojo, y
eso casi seguro significa que el login con Google no anda.

Para confirmarlo: abrir somosaurapass.com en una ventana de incógnito →
Ingresar → Continuar con Google. Si Google muestra un error del estilo
"invalid_client", "deleted_client" o "The OAuth client was not found", es esto.

## Si Google avisa que lo va a borrar (antes de que pase)

1. Entrar a Google Cloud → proyecto **somosaura-app** → *Google Auth Platform*
   (o *APIs y servicios*) → *Clientes*.
2. Abrir **Aura Web** y seguir lo que ofrece el aviso para conservarlo.
3. Iniciar sesión con Google en somosaurapass.com desde incógnito: un ingreso
   real reinicia el contador de inactividad.

## Si ya lo borraron

**Primero, intentar restaurarlo.** Google permite recuperar un cliente borrado
durante un tiempo (30 días al momento de escribir esto): en *Clientes* debería
aparecer una opción para ver los clientes eliminados y restaurarlos. Si se
restaura, mantiene el mismo client ID y secret, así que no hay que tocar
Supabase. Probar el login y listo.

**Si no se puede restaurar, crear uno nuevo (unos 10 minutos):**

1. Google Cloud → proyecto **somosaura-app** → *Clientes* → **Crear cliente**.
2. Tipo de aplicación: **Aplicación web**. Nombre: `Aura Web`.
3. **Orígenes de JavaScript autorizados:** `https://somosaurapass.com`
4. **URIs de redireccionamiento autorizados** (tiene que quedar EXACTO, sin
   barra al final):
   ```
   https://hvgqpzvornlnxmsbqnwg.supabase.co/auth/v1/callback
   ```
5. Crear. Copiar el **ID de cliente** y el **Secreto del cliente** (el
   secreto conviene descargarlo en el momento: después puede no volver a
   mostrarse completo).
6. Supabase → proyecto Aura → Authentication → Sign In / Providers →
   **Google** → pegar el Client ID y el Client Secret nuevos → **Save**. No
   tocar el resto de las opciones.
7. Probar: incógnito → somosaurapass.com → Ingresar → Continuar con Google →
   tiene que entrar a una cuenta que ya existía, con sus créditos y reservas.
   Probar también desde la app del iPhone.
8. Actualizar la tabla de arriba de este archivo con el client ID nuevo y la
   fecha.

**Las usuarias no pierden nada.** Google identifica a cada persona con el
mismo número para cualquier cliente, así que Supabase reconoce la cuenta de
siempre. No se crean cuentas duplicadas.

**La pantalla de consentimiento** (nombre "Aura", logo, dominios) es del
proyecto, no del cliente: sigue ahí aunque borren el cliente. Si Google pide
verificarla de nuevo, el nombre, el logo y los links a
https://somosaurapass.com/privacy.html y /terms.html tienen que seguir iguales.

## Mientras está roto

Las que entran con Google no tienen contraseña. Pueden tocar "¿Olvidaste tu
contraseña?" con su Gmail, crearse una y entrar con mail y contraseña a la
misma cuenta. (No probado de punta a punta con una cuenta solo de Google al
3/11/2026.)

## Verificar en la base que un login usó Google

`auth.identities.last_sign_in_at` **no sirve**: queda en la fecha de alta y no
se actualiza en cada ingreso. Lo que cambia en cada login es `updated_at`:

```sql
select u.email, i.updated_at as ultimo_ingreso_google
  from auth.identities i join auth.users u on u.id = i.user_id
 where i.provider = 'google'
 order by i.updated_at desc limit 5;
```

Es lo mismo que usa la línea del resumen diario
(`public.ultimo_ingreso_google()`).
