# Plan: preservar la facturación cuando una alumna borra su cuenta

Relevado el 2026-08-26 midiendo contra la base. **Nada aplicado todavía.**

## 1. El daño concreto, medido

**La liquidación del mes se calcula EN VIVO desde `reservas`.**
`admin_liquidaciones_screen.dart:95-148` trae las reservas del mes por
`created_at` y las suma con `Liquidacion.netoReserva`. Recién cuando se
registra la liquidación queda un snapshot en `liquidaciones`
(`monto_total_reservas`, `cantidad_reservas`).

⇒ **Hasta que el mes se liquida, lo que se le debe al estudio existe SÓLO como
filas en `reservas`.** Si una alumna borra su cuenta el día 20, el estudio
pierde ese ingreso y nadie se entera: no queda rastro.

Cuentan para plata los estados de `AppConstants.estadosLiquidables`:
`confirmada`, `presente`, `ausente`, `completada`.

## 2. Son 12 FK con CASCADE sobre 11 tablas (`referrals` tiene dos)

Medidas hoy. **Ojo: casi todas las columnas son `NOT NULL`**, así que
`SET NULL` exige antes un `drop not null` — es la parte pesada del cambio.

### Grupo A — evidencia de plata: PASAN A `SET NULL` (3)

| Tabla | Columna | Filas | Por qué |
|---|---|---|---|
| `reservas` | `usuario_id` NOT NULL | 2 | lo que se le debe al estudio |
| `pagos` | `user_id` NOT NULL | 29 | lo que la alumna le pagó a Aura |
| `creditos_movimientos` | `user_id` NOT NULL | 16 | el ledger de créditos |

### Grupo B — datos personales: SIGUEN en CASCADE (7)

`favoritos_estudios` (6) · `notificaciones_usuario` (0) · `avisos_entregas` (0)
· `estudio_admins` (23) · `admin_users` (1) · `referrals` × 2 (2).

Son suyos y no son evidencia contable. Borrarlos es lo correcto. El crédito que
un referido generó **no se pierde**: vive en `creditos_movimientos`, que ahora
sobrevive.

### Grupo C — decisión de producto, NO técnica (2)

| Tabla | Filas | La disyuntiva |
|---|---|---|
| `study_reviews` | 1 | Borrar = el estudio pierde una reseña que se ganó. Anonimizar = queda "usuaria eliminada" y el rating se sostiene. |
| `admin_activity_logs` | 55 | Es un log de auditoría. Un log que el propio auditado puede borrar no sirve como auditoría ⇒ **recomiendo `SET NULL`**. |

## 3. ⚠️ Cambiar las FK NO alcanza — y esto no estaba en la nota vieja

`supabase/functions/delete-account/index.ts` **borra las filas a mano**, antes
de que la FK opine:

- **línea 154:** `.from('reservas').delete().eq('usuario_id', uid)` — todas sus
  reservas, `completada` incluida. **Este es el agujero medido** (borrar a Male
  se llevaba una `completada` de 18 créditos facturados a Citra).
- **línea ~270:** borra explícitamente `creditos_movimientos` y `referrals`.
- **`pagos` NO está en la lista**: muere por CASCADE al borrar `usuarios`.

⇒ Si sólo tocamos el esquema, **no cambia nada** para `reservas`: el DELETE
explícito corre igual. Hay que tocar las dos mitades, y **la edge function
primero**, que es la que hace el daño hoy.

### Un segundo agujero, aparte

Cuando quien borra la cuenta es **dueña de un estudio** (líneas 160-220): por
cada clase futura hace `from('reservas').delete().eq('clase_id', claseId)` —
**todas** las reservas de la clase, sin mirar el estado, después de reembolsar
sólo `confirmada`/`pre_confirmada`. Y como borra las reservas primero, el
candado `trg_clases_bloquear_borrado` no llega a dispararse: lo saltea.
Exposición real baja (son clases futuras), pero el patrón es el mismo.

## 4. Qué pasa con el plan nuevo

Alumna toca "borrar mi cuenta":

**Se conserva, anonimizado (`usuario_id = NULL`):**
- sus reservas → el estudio cobra su mes igual
- sus pagos → la contabilidad de Aura cuadra
- sus movimientos de crédito → el ledger cierra

**Se borra de verdad:** fila de `usuarios`, fila de `auth.users`, favoritos,
notificaciones, lista de espera, referrals, roles de admin, entregas de avisos.

**Clave de privacidad:** `reservas` **no tiene ningún dato personal** además de
`usuario_id` — es `clase_id, estado, creditos_usados, codigo_qr, created_at,
checked_in_at, expires_at, creditos_lotes`. Con poner el `usuario_id` en NULL
queda **anónima de verdad**, sin nada que scrubear.

> ❌ **Descarto lo que proponía la nota vieja** ("copiar email/nombre al
> momento"). Eso **re-introduce** dato personal en la tabla que estamos
> anonimizando, justo cuando la usuaria pidió que la borren. Un número de
> transacción sin identidad es exactamente lo que hace falta para facturar.

`pagos` sí tiene dos campos personales: **`gift_email` y `gift_mensaje`** (el
mail de quien recibe la gift card y el texto). Esos hay que **limpiarlos** al
anonimizar, no sólo poner `user_id` en NULL.

## 5. Qué puede romperse — a verificar ANTES de aplicar

18 funciones tocan `reservas` + `usuario_id`. La mayoría filtran por
`auth.uid()`, así que una fila con NULL simplemente nunca matchea. Las que hay
que mirar una por una:

| Función | Riesgo |
|---|---|
| `admin_list_reservas` | va a listar filas sin usuaria ⇒ necesita mostrar "cuenta eliminada" en vez de romper |
| `admin_dashboard_metrics` | si cuenta usuarias únicas, NULL puede desviar el número |
| `estudio_cancelar_clase` | reembolsa por reserva ⇒ tiene que **saltear** las de NULL (no hay a quién devolverle) |
| `aviso_destinatarios_email` | mails de destinatarios ⇒ saltear NULL |
| `reservas_bloquear_columnas_sensibles` | el guard: que no rompa con NULL |

**RLS:** `reservas_select_own` es `auth.uid() = usuario_id`. Con NULL no
matchea a nadie ⇒ ninguna alumna ve reservas huérfanas. ✅ Y el estudio las
sigue viendo por `puede_ver_reservas_de_clase(clase_id)`, que no mira al
usuario ⇒ **la liquidación sigue funcionando**. ✅

**Dart:** hay que buscar los `as String` / `!` sobre `usuario_id` que asuman
que nunca es null.

## 6. Orden propuesto

1. **Arreglar la edge function primero** (es la que hace el daño hoy): que
   anonimice en vez de borrar `reservas`, `pagos` y `creditos_movimientos`.
   No toca esquema, es reversible, y tapa el agujero ya.
2. **Verificar las 5 funciones** de la tabla de arriba con `usuario_id` NULL,
   en transacción con `rollback`.
3. **Recién ahí el esquema:** `drop not null` + `set null` en las 3 (o 4, si
   entra `admin_activity_logs`).
4. **Probar el viaje completo** con una cuenta real de prueba: reservar →
   completar → borrar cuenta → confirmar que la liquidación del estudio sigue
   dando el mismo número.
5. **Decidir el Grupo C** (`study_reviews`) — es tuya, no técnica.

**No hace falta build de Dart** salvo que el paso 5 lo pida: la edge function
se despliega sola y el esquema es base.
