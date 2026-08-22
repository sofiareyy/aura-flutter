# 👉 RETOMAR ACÁ

**ESTADO:** abierto · **Verificado contra la base:** 2026-08-22

Punto de entrada de la próxima sesión. Único lugar donde viven los pendientes.
Escrito para arrancar sin re-pensar.

---

# ✅ PASO 0 — AUDITORÍA COMPLETA: HECHA (2026-08-22)

Las 8 áreas medidas contra la base. **Resultado: la base está sana.** Las áreas
de plata directa —pricing, reservas, RLS— resistieron todo, incluidos 6
exploits corridos con el JWT del dueño real de una reserva.

| Área | Estado |
|---|---|
| 1 · Pricing (5 arreglos del 22/8) | ✅ todo en pie |
| 2 · Farmeo del vencimiento | ⚠️ **fuga lateral** |
| 3 · Foto de perfil | ⚠️ correcta pero **nunca ejercitada** |
| 4 · Vencimiento de packs | ✅ ok |
| 5 · Escritura de reservas | ✅ 6/6 exploits bloqueados |
| 6 · CASCADE de usuarios | ⚠️ **confirmado abierto** |
| 7 · Los 6 crons | ✅ con asterisco |
| 8 · Storage y RLS | ✅ muy bien |

**Lo que se confirmó bien:** triggers y CHECK de pricing en pie con 0 clases
desviadas; 6 de 6 exploits de reserva bloqueados (bajar el precio, auto-
cancelarse, cambiar el QR, mover la reserva, borrarla, crear una gratis); todas
las tablas públicas con RLS y todo lo sensible invisible para un anónimo —los
CBUs ni llegan a RLS, dan `permission denied` a nivel de grant—; y cero fallas
de cron después del 21/8.

## Los 6 hallazgos nuevos

1. **Fuga en `admin_adjust_user_credits`.** Es la única función que escribe en
   `creditos_movimientos` sin pasar por `grant_user_credits`, y mete
   `expires_at = null` hardcodeado: **cada crédito regalado a mano no vence
   nunca**. Hay 5 movimientos eternos, todos `source='manual'`, todos previos
   al fix, con **29 créditos vivos** (20 de `julietarey2002@gmail.com`).
2. **La foto de perfil nunca se ejercitó.** Policies y buckets correctos
   (`{userId}/...`, 10MB, `image/*`), pero **0 archivos y 0 `avatar_url`**.
   Está bien configurada; no está probada.
3. **No hay policy de DELETE en `storage.objects`** para ningún bucket. El
   servidor borra (service_role saltea RLS), el cliente no.
4. **Los 3 crons mensuales no corrieron desde el fix.** Últimas ejecuciones el
   1/8 y el 4/8, *antes* del 21/8. Y dos de ellos son los que le mandan mails a
   los estudios, con próxima corrida pegada al inicio del cobro.
5. **`pack_credits_expiration`** está muerta con 3 sobrecargas de tipos
   ambiguos y cero llamadores.
6. **`vigencia_dias`** no se actualiza en `admin_upsert_pricing_pack`, así que
   se desincroniza de `vencimiento_dias` al editar un pack.

**El patrón que comparten los tres con sustancia:** son puertas laterales que
quedaron abiertas cuando se cerró la principal — el grant manual junto al
farmeo, el `delete-account` junto al cascade, y el `tipo` junto al precio.
Reflejo para la próxima: **cuando cierres un camino, buscá quién más escribe en
la misma tabla.**

## Números de referencia (22/8, post-auditoría)
885 clases · 70 horarios fijos · 5 reservas (4 canceladas) · 9 estudios ·
0 experiencias futuras · 0 clases desviadas de la regla · rangos 11–50 y 11–18 ·
78 usuarios · 6 pagos aprobados por $84.220.

---

# 🔴 ORDEN DE ARREGLO

## Tanda 0 — antes del 1/9 · CERRADA salvo el aviso

1. ✅ **Los 3 crons mensuales, verificados el 22/8.**
   `acreditar-creditos-corporativos` corrido de verdad: 200 OK, `{empresas:0}`.
   Con eso quedo probado el camino cron → Vault → edge function, identico en
   los tres. **`aviso-cobro-manana` estaba ROTO** y se arreglo (ver abajo).
   `reporte-mensual-estudios` verificado por simulacion SQL y dry-run.

2. ✅ **Correo — resuelto SIN tocar DNS.**
   El SPF que iba a agregar **ya existia**: Resend lo pone en
   `send.somosaurapass.com`, no en el apex. Junto con el DKIM
   (`resend._domainkey`) y el DMARC, la autenticacion estaba completa. Lo unico
   roto era que `hola@somosaurapass.com` **no recibe** (apex sin MX, A de
   GitHub Pages) y esa direccion figuraba en el pie de los mails.
   Se cambio el pie a `aura.hola.app@gmail.com` —que ya era la direccion de
   soporte de la app y la web, o sea que ademas **unifico** dos direcciones que
   estaban peleadas— y se sumo `reply_to` en las 6 funciones. Sin DNS.

3. ⬜ **Avisar el fin de la gracia.** Lo unico que queda. Citra el 13/9.
   Ver `aura-avisar-fin-de-gracia` en memoria: 6 estudios entre el 13/9 y el
   30/9, transicion automatica, falta la conversacion.

### Lo que salio de la Tanda 0 y hay que tener presente

- **`email-confirmacion` NO esta deployada en produccion.** Existe en el repo,
  nunca se subio. Es la que manda la confirmacion de reserva al usuario.
  Revisar si es intencional antes de subirla.
- **La trampa del `config.toml`:** aparecio dos veces. Una funcion no declarada
  ahi cambia su `verify_jwt` en silencio al deployar. Quedaron declaradas
  aviso-cobro-manana, reporte-mensual-estudios, aviso-alumnos-email y
  email-regalo. **Antes de cualquier `functions deploy`, chequear que la
  funcion este declarada.**
- **Arranque en frio:** la primera invocacion despues de un deploy corta a los
  5s por el default de `pg_net`. No rompe el cron; para ver la respuesta hay
  que pasar `timeout_milliseconds := 30000`.
- **Las 2 funciones de mail a estudios aceptan `{"dry_run": true}`**: arman el
  reporte y devuelven a quien le habrian escrito, sin mandar mail.

## Tanda A — el barrido de base (1 sesión, sin decisiones)

1. La **fuga de `admin_adjust_user_credits`** + qué hacer con los 29 créditos eternos.
2. **Las etiquetas de Sculpt**: primero sacar el `v_tipo := 'normal'` hardcodeado
   de `generar_clases_estudio`, **después** el backfill de las 72. En ese orden,
   o el cron de las 03:00 las repone esa noche.
3. **El índice** `reservas_usuario_clase_uidx` → `NOT IN ('cancelada','cancelada_por_estudio')`.
4. **`ensure_referral_code`** sin `search_path` — la auditoría confirmó que es la última.
5. **Whitelist de estados** del estudio (no hay ningún CHECK).
6. **Código muerto:** `admin_update_global_credit_value` y `pack_credits_expiration`.
7. **Columna fantasma** `clases."lugares_ disponibles"` (el Dart va después).
8. **Datos:** backfill de las 189 clases sin categoría, `creditos_por_categoria`
   legacy, y `vigencia_dias` en el upsert de packs.

## Tanda B — verificación de mail
Va **antes** del build: probablemente necesite una pantalla de "revisá tu mail",
y descubrirlo después es perder el release. `mailer_autoconfirm = true`
confirmado. **Medir antes de tocar el toggle** o rompés el registro de todos.

## Tanda C — el build de Dart (todo junto, un release)
Encabeza **el texto de "gratis"** (captación). Detalle completo en
`DART_PENDIENTE_proximo_build.md`. Sumar de la auditoría: **probar que la foto
de perfil funcione de verdad**, porque no hay un solo archivo subido.

## Tanda D — Modelo C → destraba los running clubs
Ver `aura-running-club-caso-de-uso-modelo-c` en memoria. La excepción tiene que
admitir cero y ser respetada por los **dos** triggers **y** por
`generar_clases_estudio`, o el cron la pisa.

## Tanda E — experiencias, esquema pesado y el resto
Experiencias (⚠️ hay **cero experiencias futuras**: decidir si el cuello es
descubrimiento u oferta), preservar facturación (12 tablas CASCADE, incluidas
`pagos` y `reservas`), keys legacy (sólo queda la `anon` de la app), y la firma
del webhook de MP.

## Mantenimiento
Sanear los docs de esta carpeta, y escribir el doc de eventos gratis (no existe;
ya hay material: la medición end-to-end con saldo 0 está hecha).

---
# Lo que se cerró el 2026-08-22 — tanda de pricing

Los cinco aplicados en producción y verificados con tabla temporal + rollback,
las dos puntas cada uno. **Ninguna fila de producción se movió.**

| | Arreglo | Migración |
|---|---|---|
| 🔴 | Bypass del `tipo`: workshop caro → clase sin repreciar | `20260822140000_precio_cierra_bypass_tipo.sql` |
| 🔴 | Sin precio configurado no se cargan clases (se acabó el 10 escondido) | `20260822150000_precio_rechaza_estudio_sin_precio.sql` |
| 🟠 | CHECK de sanidad 0–500 en las dos tablas, validado | `20260822160000_precio_check_sanidad_creditos.sql` |
| 🟠 | Fuera el `default 10` de `horarios_fijos.creditos` | `20260822170000_precio_saca_default_10.sql` |
| 🟢 | Monitoreo de arbitraje de comisión (no bloquea) | `MONITOREO_arbitraje_workshops.sql` |

**Lo que quedó demostrado y conviene no re-discutir:**
- El pico/valle automático **ya funciona** en clases normales. El estudio no
  elige el precio: lo pone la regla según día y hora. Verificado sobre 884
  clases, 0 desvíos.
- Sculpt Club es el único en modo `rango` (valle 14 / pico 16, 30 franjas).
  Los otros 8 en modo fijo.
- **Un usuario con saldo 0 puede reservar un evento gratis de punta a punta**:
  reserva confirmada, QR, aparece en "mis reservas", cupo descontado, saldo
  intacto, 0 movimientos en el ledger. No hay ningún gate de pack ni de
  suscripción. Medido con un usuario real.

---

# Lo que se cerró el 2026-08-21

| | Fix | SQL |
|---|---|---|
| 🔴 | `reservas`: UPDATE libre + INSERT gratis | `FIX_RESERVAS_ESCRITURA_CLIENTE_2026-08-21.sql` |
| 🔴 | Borrado en cascada de `usuarios` | `FIX_TANDA2_2026-08-21.sql` |
| 🔴 | 5 crons con 401 (Vault) | `FIX_CRONS_VAULT_2026-08-21.sql` |
| 🔴 | Borrado de cuenta roto por gift cards | commit `120b956` |
| 🔴 | Farmeo del vencimiento + créditos eternos | `FIX_FARMEO_VENCIMIENTO_2026-08-21.sql` |
| 🟠 | Storage acotado + límites | `FIX_TANDA2_2026-08-21.sql` |
| 🟠 | Foto de perfil | `FIX_FOTO_PERFIL_2026-08-21.sql` |
| 🟠 | Vencimiento de packs a 90 días | `FIX_VENCIMIENTO_PACKS_2026-08-21.sql` |
| 🟠 | Tabla `resenas` legacy | borrada |

---

# FEATURES EN DISEÑO

## 1. Modelo C de pricing — la excepción de precio

**Decidido el 22/8.** Precio automático por franja (ya funciona) **más una
excepción explícita que sólo Aura puede levantar**.

**El caso de uso concreto que lo vuelve necesario: el running club gratis.**
Clase recurrente y gratis, hoy imposible de cargar — y **no por los arreglos de
esta tanda**: la bloquea el trigger de precio, que pisa `creditos` con el
precio del estudio. Probado: pedir una clase en 0 en Citra dejó 18.
Configurarle precio al estudio no ayuda; es justamente lo que le pone precio.

Las tres salidas de hoy y por qué ninguna sirve:
- **Como experiencia a 0 pesos:** anda ya, pero los workshops **no pueden
  repetirse** y caen en Experiencias, no entre las clases.
- **Por SQL:** anda, pero el cron de las 03:00 crea la semana nueva del borde a
  precio del estudio. Se vuelve pago de a una semana por vez.
- **Modelo C:** la buena.

⚠️ Al diseñarlo: la excepción tiene que admitir cero y ser respetada por los
**dos** triggers **y** por `generar_clases_estudio`, si no el cron la pisa.

Quedan además **7 decisiones de borde** (clases al límite de franja, estudios
sin valle, recálculo del pasado, etc.) en el documento de pricing.

## 2. Experiencias: categorías y buscador propios

Sólo lado **usuario** (descubrir), nunca lado estudio (cargar) — el botón de
cargar está escondido a propósito por el 15% vs 30%.

Lo medido:
- Las experiencias **son `clases` con `tipo='workshop'`**: misma tabla, mismas
  reservas, **y ya usan el mismo `categorias text[]`**. A nivel dato no hay
  nada que construir.
- Explorar **las excluye** (`clases_service.dart:23`).
- **El filtro de categorías filtra ESTUDIOS, no clases** — es el habilitador
  que falta, y para experiencias es bloqueante (la categoría de un taller de
  cerámica nunca coincide con la del estudio de yoga).
- 190 de 589 clases futuras no tienen ninguna categoría.
- Las experiencias son las únicas con foto propia (9 de 589 clases tienen
  imagen; la única experiencia tiene foto, galería y descripción larga).
- ⚠️ **Hay una sola experiencia futura en toda la base.** Un buscador sobre un
  item no se puede evaluar. Decidir si el cuello es descubrimiento u oferta.

## 3. Running clubs como categoría dentro de clases

`Running` y `GRATIS` **ya existen** en `study_categories`. Pero hoy son chips
muertos: ningún estudio los tiene y el filtro mira estudios. Bloqueado por el
mismo habilitador que las experiencias, más el Modelo C para el precio 0.

## 4. Cartel de "clase gratis" + consumo aparte

Reusar el slot de `detalle_clase_screen.dart:736` (la tarjeta verde de "Reserva
gratuita"), resolviendo la precedencia contra `_esGratuita`, que significa otra
cosa (alumno del estudio en modo gestión, por usuario y no por clase).
Más una nota corta del estudio para el café de después, con prefijo fijo de
Aura. **El badge tiene que estar en el listado, no sólo en el detalle**, o se
lee como carnada.

---

# PASO 1 — Verificación de mail (viene de la Sesión 1)

`mailer_autoconfirm = true`: hoy cualquiera se registra con un mail que no es
suyo y queda confirmado al instante.

**Cierra tres caminos de plata** (hoy en cero, pero se arman solos):

| Camino | Mecanismo | Se activa cuando |
|---|---|---|
| Créditos corporativos | `trg_vincular_usuario_empresa` → `grant_user_credits` por dominio | sumes la primera empresa |
| Reservas gratis | `reservar_clase`: estudio en modo `gestion` + mail en `estudio_alumnos` ⇒ 0 créditos | un estudio pase a modo gestión |
| Gift cards | `canjear_regalo` valida contra `auth.users.email` | haya gift cards sin canjear |

### ⚠️ Por qué no es sólo tocar el toggle

**La app tiene que manejar el estado "registrado sin confirmar".** Hoy asume que
el login post-registro funciona directo. Si no lo maneja, **rompés el registro
para todos los usuarios nuevos.**

### Medir primero, con el toggle apagado

1. `register_screen.dart`: ¿qué hace si `signUp` devuelve `session == null`?
2. ¿Existe pantalla o cartel de "revisá tu mail"? Si no, hay que hacerla (build).
3. ¿Qué pasa si alguien intenta loguearse sin confirmar? (`email_not_confirmed`)
4. OAuth no se ve afectado: llega con el mail verificado. Confirmarlo.
5. `emailRedirectTo` → `AppConstants.auraWebUrl`, y en la allowlist.

---

# Más adelante

- **`PRESERVAR_FACTURACION.md`** — cambio de esquema, el más pesado
- **`SANEAR_ESTOS_DOCS.md`** — mantenimiento de esta carpeta
- **Devoluciones y vencimiento** — 5 reglas distintas + créditos eternos.
  Postergado al build 22 a propósito, **no re-proponer**
- **Avisar el fin de la gracia** — 5 estudios empiezan a pagar 30% el 1/10/2026
- **Último admin de un estudio** — mejora de prioridad baja, no re-proponer

---

# Estado del repo al cerrar (2026-08-22)

`main` sincronizado. La tanda de pricing (4 migraciones) y la limpieza de
reservas ya están **aplicadas en producción**; los archivos son el registro.

⚠️ **Verificar siempre contra la base, nunca contra los archivos.** Acá las
migraciones se aplican a mano, así que un `.sql` en el repo no prueba que esté
aplicado. Usar `pg_get_functiondef` / `pg_trigger` / `pg_constraint`. Ese error
costó tres tropiezos esta semana. Ver `aura-sql-produccion-management-api`.

Plan completo con las 8 áreas y el orden:
https://claude.ai/code/artifact/85e0bcd6-dc65-4912-aae2-40371ad2e618
