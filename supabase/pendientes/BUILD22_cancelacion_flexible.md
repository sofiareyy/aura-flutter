# Build 22 — Cancelación flexible

Hallazgos del 2026-08-14, durante el chequeo de vencimientos del build 21.
**No se tocó nada de código.** La usuaria decidió que esto es parte de la
feature de cancelación flexible y merece su propia sesión, no el final de una
sesión larga tocando la función por la que pasa toda la plata.

---

## El problema

Hay **5 caminos de devolución de créditos**, cada uno con su propia regla de
vencimiento, y ninguna respeta lo que la persona compró:

| Camino | Dónde | Vence hoy |
|---|---|---|
| `rollback_reserva` | `d1_cerrar_agujeros_criticos.sql:143` (`reservar_clase`) | **`null` — nunca** 🔴 |
| `devolucion_cancelacion` | `d1_cerrar_agujeros_criticos.sql:249` (`cancelar_mi_reserva`) | 60 días |
| `devolucion_clase_cancelada` | `d1_cerrar_agujeros_criticos.sql:316` (`estudio_cancelar_clase`) | 90 días |
| `eliminacion_cuenta` | `supabase/functions/delete-account/index.ts:115` | 60 días |
| Estudio cerrado | `supabase/functions/delete-account/index.ts:194` | 90 días |

Cada devolución **crea un lote nuevo** en `creditos_movimientos` con una fecha
inventada, en vez de devolver los créditos al lote del que salieron.

**Consecuencia concreta:** con Pack Prueba (30 días), reservar y cancelar
devuelve los créditos con 60 días. Repitiendo la maniobra se estiran
indefinidamente.

---

## 🔴 Prioridad alta: `rollback_reserva` hace créditos eternos

De los cinco, este es el peor y va primero.

```sql
-- reservar_clase, cuando apply_reservation falla
perform public.grant_user_credits(
  v_uid, v_creditos, 'rollback_reserva', null,   -- ← null = no vence NUNCA
  'Devolucion por reserva fallida'
);
```

Un `expires_at` en `null` significa "sin vencimiento" en todo el ledger
(`consume_user_credits` los ordena `nulls last`, o sea que se gastan al final,
y `refresh_user_credit_balance` nunca los pone en cero). Cada vez que
`apply_reservation` falla, esa persona se queda con créditos inmortales.

---

## El arreglo propuesto

Que las devoluciones **rellenen el lote original** en vez de crear uno nuevo,
respetando su vencimiento. Se vuelve exactamente al estado anterior a la
reserva: ni se gana ni se pierde.

La propuesta completa, ya escrita y comentada, está en
**`BUILD22_devoluciones_PROPUESTA.sql`** (en esta misma carpeta, fuera de
`migrations/` a propósito para que no se aplique sola).

En resumen:

- Función nueva `restore_user_credits`, que recorre los lotes consumidos y
  todavía vigentes en orden `expires_at asc nulls last` — el inverso exacto
  del que usa `consume_user_credits` para gastar— y los rellena hasta
  `amount_total`, nunca más.
- `grant_user_credits` deriva a esa función cuando el `source` es una de las
  cuatro devoluciones. Arregla los 5 caminos de una, incluidos los dos que
  están en TypeScript, sin redeployar `delete-account` ni reescribir
  `reservar_clase` / `cancelar_mi_reserva` / `estudio_cancelar_clase`.

**Cuidado al retomar:** `grant_user_credits` no está en ninguna migración (se
creó desde el dashboard). El cuerpo actual está transcripto dentro de la
propuesta; verificar contra la base antes de reemplazarla, porque puede haber
cambiado.

---

## ⚠️ Decisión de negocio pendiente

**Si cancelás una reserva cuyo lote original ya venció, ¿qué pasa?**

Ejemplo: comprás Pack Prueba (30 días), reservás el día 28, cancelás el día 35.

- **Generoso** — se devuelven en un lote nuevo con 60/90 días. Argumento: los
  créditos estaban vivos cuando reservó, no es justo que pierda por cancelar.
- **Estricto** — se pierden. Argumento: habrían vencido igual, la reserva no
  los tenía que salvar.

La propuesta actual está escrita en modo **generoso**, pero es un `if` de tres
líneas cambiarlo. **Definirlo antes de implementar.**

---

## Lo que NO hay que hacer

No tocar los datos existentes. `test@aura.com` tiene un lote de 90 días de
junio de 2026, anterior a la migración D1. Es historia real y se queda como
está.
