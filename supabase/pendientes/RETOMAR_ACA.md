# 👉 RETOMAR ACÁ

**ESTADO:** abierto · **Verificado contra la base:** 2026-08-22

Punto de entrada de la próxima sesión. Único lugar donde viven los pendientes.
Escrito para arrancar sin re-pensar.

---

# ⛳ PASO 0 — LA AUDITORÍA COMPLETA

**Es lo primero de la próxima sesión.** Con cabeza fresca, medida contra la
base como las anteriores. Se postergó a propósito el 22/8 porque la sesión ya
venía larga.

No es una auditoría de seguridad nueva: es **verificar que lo que se tocó
estos días sigue en pie y no rompió nada al costado.** Se tocaron muchas cosas
en pocos días y ninguna se volvió a mirar en conjunto.

## Áreas a cubrir

### 1. Pricing — los 5 arreglos del 22/8
Los cinco se aplicaron y se verificaron uno por uno, pero nunca juntos.
- Los dos triggers instalados, activos y con el código vivo igual al del repo
  (`pg_get_functiondef`, no confiar en los archivos: **las migraciones acá se
  aplican a mano**)
- `clases_creditos_sanos` y `horarios_fijos_creditos_sanos` con
  `convalidated = true`
- `horarios_fijos.creditos` sin default
- 0 clases desviadas de la regla; ninguna fuera de 0–500
- Que ningún estudio quedó sin poder cargar
- Que las experiencias siguen con precio libre (no las tocamos a propósito)
- **Que reservar sigue funcionando**, sobre todo con saldo 0 en evento gratis

### 2. Farmeo del vencimiento (21/8)
`FIX_FARMEO_VENCIMIENTO_2026-08-21.sql`. Que cancelar una reserva **no** renueve
el vencimiento de los créditos y que no queden créditos eternos. Es el que más
plata mueve de los del 21.

### 3. Foto de perfil (21/8)
`FIX_FOTO_PERFIL_2026-08-21.sql` — nunca había funcionado. Que las policies del
bucket `avatares` estén y que una subida real ande. Queda el `DART_FOTO_PERFIL.md`
para el build.

### 4. Vencimiento de packs a 90 días (21/8)
`FIX_VENCIMIENTO_PACKS_2026-08-21.sql`. Que editar un pack no le resetee el
vencimiento.

### 5. Escritura de `reservas` desde el cliente (21/8)
`FIX_RESERVAS_ESCRITURA_CLIENTE_2026-08-21.sql`. Que el UPDATE libre y el INSERT
gratis sigan cerrados.

### 6. Borrado en cascada de `usuarios` (21/8)
`FIX_TANDA2_2026-08-21.sql`. **Y el riesgo conocido que sigue abierto:** si un
alumno borra su cuenta, el CASCADE se lleva la deuda al estudio. Verificar si
quedó cubierto o sigue vivo.

### 7. Los 6 crons
Al 22/8 los seis figuran activos:
`regenerar-grillas-diario` (03:00), `completar-reservas` (cada hora),
`cleanup-lista-espera-15min`, `aviso-cobro-manana`,
`acreditar-creditos-corporativos-mensual`, `reporte-mensual-estudios`.
Verificar que **corrieron de verdad**, no sólo que están agendados (fue el bug
de los 401 por Vault).

### 8. Storage y RLS general
Límites de storage del 21/8, y un barrido de policies sobre las tablas que se
tocaron.

## Datos de referencia al 22/8 (para comparar)
885 clases · 70 horarios fijos · 5 reservas · 9 estudios · 1 experiencia ·
0 clases desviadas de la regla · rangos 11–50 (clases) y 11–18 (horarios).

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

# PENDIENTES POR PRIORIDAD

## 🔴 Alta — base, sin build

| Qué | Detalle |
|---|---|
| **Verificación de mail** (`mailer_autoconfirm`) | Ver PASO 1 abajo. **Medir antes de tocar el toggle**: si la app no maneja "registrado sin confirmar", rompés el registro para todos los nuevos |
| **Firma del webhook de MP** | Hoy se calcula y **se descarta**: `if (signature && !valid) console.warn(...)` sin cortar, y el branch GET ni la evalúa. Requiere redeploy de la edge |
| **`ensure_referral_code` sin `SET search_path`** | El último SECURITY DEFINER que falta, alcanzable por `authenticated` |
| **`cancelada_por_estudio` en `reservas_usuario_clase_uidx`** | El índice excluye sólo `'cancelada'` ⇒ si el estudio cancela y reabre, la usuaria **no puede volver a reservar**. Pasar a `NOT IN ('cancelada','cancelada_por_estudio')` |
| **CASCADE borra la deuda al estudio** | Si un alumno borra su cuenta se lleva lo que el estudio tenía por cobrar. Verificar en la auditoría si sigue vivo |

## 🟠 Media — base, sin build

| Qué | Detalle |
|---|---|
| **Packs hardcodeados** | La app **calcula** el precio (`_packsBase` en `pricing_service.dart`) en vez de leer `pricing_credit_packs`. Desde el build 21 `crear-checkout-pack` rechaza si no coincide exacto ⇒ **el día que subas `valor_credito_ars` se bloquean todas las compras de packs**. Hoy anda de casualidad porque está en 1000 |
| **Limpiar reservas de prueba** | Al 22/8: **4 reservas completadas en Hot Clic, 47 créditos** — le muestran al estudio ~$33.000 falsos a cobrar. (La nota vieja decía 3 y $24.500: creció) |
| **Borrar la RPC muerta `admin_update_global_credit_value`** | 0 llamadores; desincroniza `configuracion_global` |
| **Borrar la columna fantasma `clases."lugares_ disponibles"`** (con espacio) | Verificada el 22/8: **sigue existiendo**. 0 filas con dato. El Dart la nombra en 8 lugares, siempre con `??` después de la correcta ⇒ borrar la columna es seguro; limpiar el Dart va después (build) |
| **Whitelist de estados del estudio** | `WHITELIST_ESTADOS_ESTUDIO.md`. Que no se pueda revivir una `cancelada` a estado facturable |
| **Las 66 etiquetas `tipo_precio` de Sculpt** | Dicen `normal` estando el estudio en `rango`. El precio está bien, la etiqueta no. Causa: el recálculo refresca `horarios_fijos.creditos` pero no su `tipo_precio`, y el generador copia el label viejo. Es un `UPDATE` |
| **Correo saliente: SPF + Reply-To** | `CORREO_SALIENTE.md`. `somosaurapass.com` no tiene MX ni SPF |

## 🔵 Dart — todo junto en UN solo build

Detalle completo en **`DART_PENDIENTE_proximo_build.md`**. Resumen:

| Qué | Por qué importa |
|---|---|
| **Propagar el mensaje del servidor al crear clase** | `mis_clases_screen.dart:1975` descarta el mensaje humano del arreglo #2 y muestra "Intentá de nuevo" |
| **Badge "PRECIO REDUCIDO"** | Sale en **578 de 589** clases. Vacía el argumento de venta de pico/valle justo ahora |
| **"Ver todas" de Experiencias** | `home_screen.dart:768` lleva a `/explorar`, la única pantalla que las excluye |
| **Los ceros de las clases gratis** | Una clase de 0 no dice "gratis" en ningún lado: dice `0 cr`, `Reservar · 0 créditos` y `Canjear · 0 créditos`. **Para captar gente que baja la app sin comprar, esto no es cosmético** |
| Cartel de lista de espera | `LISTA_ESPERA_arreglar_y_asegurar.md` |
| Modo visita Pieza C | `MODO_VISITA_pieza_A.md` |
| Limpieza de la foto de perfil | `DART_FOTO_PERFIL.md` |
| Las 8 referencias a la columna fantasma | Después de borrarla en base |
| Salir de las keys legacy | `SALIR_DE_KEYS_LEGACY.md` |

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

`main` sincronizado con `origin/main` en `8f5fae2`.

**Sin commitear ni pushear — 6 archivos nuevos de esta sesión:**

```
supabase/migrations/20260822140000_precio_cierra_bypass_tipo.sql
supabase/migrations/20260822150000_precio_rechaza_estudio_sin_precio.sql
supabase/migrations/20260822160000_precio_check_sanidad_creditos.sql
supabase/migrations/20260822170000_precio_saca_default_10.sql
supabase/MONITOREO_arbitraje_workshops.sql
supabase/pendientes/DART_PENDIENTE_proximo_build.md
```

⚠️ **Los cuatro cambios de base YA ESTÁN APLICADOS en producción.** Los archivos
son el registro, no la fuente. Si se pierden, la base igual quedó cambiada —
por eso conviene commitearlos antes de cerrar.

Documento de pricing con los tres modelos y las 7 decisiones de borde:
https://claude.ai/code/artifact/2ce02720-525c-438e-b839-6d317f79e4b1
