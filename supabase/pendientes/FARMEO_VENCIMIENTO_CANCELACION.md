# ✅ CERRADO — farmeo del vencimiento por cancelación

**ESTADO:** cerrado · **Verificado contra la base:** 2026-08-21

Aplicado el 2026-08-21 en `supabase/FIX_FARMEO_VENCIMIENTO_2026-08-21.sql`.
Verificado **12/12** contra producción, con rollback y midiendo efecto.
Arrastró también los créditos eternos de `rollback_reserva`.

Decisiones tomadas: (1) lote vencido se devuelve igual, en una fila nueva con
la fecha original ya pasada — visible y no farmeable; (2) reservas anteriores
usan el vencimiento más corto vivo; (3) FEFO, que ya era así.
NO se tocó `estudio_cancelar_clase`: ahí cancela el estudio y la usuaria es la
perjudicada.

<details>
<summary>El plan original (ya ejecutado)</summary>

Fecha de la nota: 2026-08-21. **Todo servidor, NO necesita build.**
Escrito para ejecutar sin re-pensar: el plan, el SQL y la verificación están
completos abajo.

---

## El problema

Cancelar una reserva **renueva el vencimiento de los créditos**. Reservar y
cancelar es un loop de dos toques que le da vida nueva a créditos que estaban
por vencer, indefinidamente.

```sql
-- cancelar_mi_reserva, hoy
perform public.grant_user_credits(
  v_uid, v_creditos, 'devolucion_cancelacion',
  (v_ahora + interval '60 days')::text,   -- ← 60 días NUEVOS, siempre
  'Devolución — ' || v_nombre
);
```

### Medido el 2026-08-21 (con rollback)

```
ESTADO INICIAL   lote de 18 créditos, vence 2026-08-22 (mañana)
1) reservar      ok  →  el lote original queda en 0
2) cancelar      ok, devolvió 18 créditos
3) lote NUEVO    18 créditos, vence 2026-10-20
   ganancia      +59 días, en dos toques
```

Y el loop se repite: 3 vueltas seguidas, todas exitosas.

**No hay ningún tope de cancelaciones** — se buscó en la base y en el código.
La única restricción es la ventana de cancelación (12 hs antes de la clase en 8
de los 9 estudios, 1 hora en Yessi Funes), y había **584 clases futuras**
disponibles fuera de esa ventana.

### Qué tan explotado está hoy: nada

| | |
|---|---|
| Filas `devolucion_cancelacion` en el ledger | **1** (15 créditos) |
| Usuarios con ledger | 4 |
| Con lotes de fechas distintas | **1**, y es `test@aura.com` |
| Usuarios reales | los 3 tienen **spread = 0** (una sola fecha) |

**No es urgente, pero hay que cerrarlo.** No requiere mala fe: cualquiera que
cancele por motivos legítimos también renueva. Y anula el modelo de
vencimiento: los packs de 30/45/45/60 días valen lo mismo que uno sin
vencimiento para quien conozca el truco.

> **Nota sobre la tasa de explotación:** no se llegó a medir una cifra de
> "créditos por mes" ganables. Lo que está medido es lo de arriba: +59 días por
> ciclo, sin tope de ciclos, y 0 explotación registrada a la fecha. Cualquier
> número de "créditos/mes" que aparezca en otro lado no salió de esta medición.

---

## Por qué NO se hizo el parche rápido

Se evaluó una **Opción 1**: devolver con `min(expires_at)` de los lotes vivos
del usuario, en vez de 60 días nuevos. Se descartó porque **tiene su propio
agujero**, encontrado antes de aplicarla:

```
1 ago   lote A: 18 cr, vence el 20
        lote B: 50 cr, vence el 30
19 ago  reservás    → A se drena a 0 (su fila queda, vence el 20)
21 ago  cancelás    → A ya venció, sale del min → la devolución hereda el 30
        resultado: créditos que morían el 20 ahora viven hasta el 30
```

Farmeo más lento pero real: se estira hasta la distancia al siguiente lote más
corto (~30 días con los packs actuales), y se reabre cada vez que se compra un
pack largo. **Aplicarla habría sido dejar el problema a medias.**

---

## LA SOLUCIÓN — rastrear el crédito exacto por reserva

Congelar, al reservar, **de qué lotes salieron los créditos y cuántos de cada
uno**. Al cancelar, devolverlos **a esos mismos lotes**. Así no importa qué
pase entre la reserva y la cancelación: no hay fecha que recalcular.

### Paso 1 — la columna

```sql
alter table public.reservas
  add column if not exists creditos_lotes jsonb;

comment on column public.reservas.creditos_lotes is
  'De qué lotes de creditos_movimientos salieron los créditos de esta reserva '
  'y cuántos de cada uno: [{"id":123,"taken":10},...]. Se llena al reservar y '
  'se usa al cancelar para devolver a los MISMOS lotes, sin renovar '
  'vencimientos. NULL en reservas anteriores al 2026-08-21.';
```

Aditiva y nullable: no rompe nada, el Dart no la lee (se verificó: 20 usos de
`creditos_usados` en Dart, ninguno de esta columna).

### Paso 2 — que el consumo informe qué tomó

`consume_user_credits` hoy devuelve `boolean`. **No se le cambia la firma**
(tiene 2 llamadores); se agrega una versión detallada y la vieja queda como
envoltorio.

```sql
create or replace function public.consume_user_credits_detallado(
  p_user_id uuid, p_amount integer
) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare
  v_needed int := p_amount; v_row record; v_take int; v_avail int;
  v_lotes jsonb := '[]'::jsonb;
begin
  if p_amount is null or p_amount <= 0 then
    return jsonb_build_object('ok', false, 'error', 'monto_invalido');
  end if;
  perform public.refresh_user_credit_balance(p_user_id);
  select coalesce(sum(amount_remaining),0) into v_avail
    from public.creditos_movimientos
   where user_id = p_user_id and amount_remaining > 0
     and (expires_at is null or expires_at >= current_date);
  if v_avail < p_amount then
    return jsonb_build_object('ok', false, 'error', 'sin_creditos');
  end if;
  for v_row in
    select id, amount_remaining from public.creditos_movimientos
     where user_id = p_user_id and amount_remaining > 0
       and (expires_at is null or expires_at >= current_date)
     order by expires_at asc nulls last, created_at asc, id asc
  loop
    exit when v_needed <= 0;
    v_take := least(v_row.amount_remaining, v_needed);
    update public.creditos_movimientos
       set amount_remaining = amount_remaining - v_take
     where id = v_row.id;
    v_lotes := v_lotes || jsonb_build_object('id', v_row.id, 'taken', v_take);
    v_needed := v_needed - v_take;
  end loop;
  perform public.refresh_user_credit_balance(p_user_id);
  return jsonb_build_object('ok', true, 'lotes', v_lotes);
end $$;
```

### Paso 3 — guardar el detalle al reservar

En **`reservar_clase`** y en **`confirm_pre_reserva`**, reemplazar:

```sql
v_consumido := public.consume_user_credits(v_uid, v_creditos);
if not coalesce(v_consumido, false) then
  return jsonb_build_object('ok', false, 'error', 'sin_creditos');
end if;
```

por:

```sql
v_det := public.consume_user_credits_detallado(v_uid, v_creditos);
if not coalesce((v_det->>'ok')::boolean, false) then
  return jsonb_build_object('ok', false, 'error', 'sin_creditos');
end if;
v_lotes := v_det->'lotes';   -- se guarda en reservas.creditos_lotes
```

- En `reservar_clase`: `apply_reservation` inserta la fila, así que hay que
  pasarle `v_lotes` **o** hacer un `update reservas set creditos_lotes = v_lotes
  where id = (v_res->'reserva'->>'id')::bigint` justo después.
- En `confirm_pre_reserva`: agregar `creditos_lotes = v_lotes` al UPDATE que ya
  hace (el que setea `estado` y `creditos_usados`).

### Paso 4 — devolver a los mismos lotes al cancelar

En **`cancelar_mi_reserva`**, reemplazar el `grant_user_credits(... 60 days ...)`
por:

```sql
if v_reserva.creditos_lotes is not null then
  -- devolución exacta: cada lote recupera lo suyo, con su vencimiento original
  update public.creditos_movimientos m
     set amount_remaining = m.amount_remaining + (l->>'taken')::int
    from jsonb_array_elements(v_reserva.creditos_lotes) l
   where m.id = (l->>'id')::bigint;
  perform public.refresh_user_credit_balance(v_uid);
elsif v_creditos > 0 then
  -- reservas viejas sin detalle: se mantiene el comportamiento actual
  perform public.grant_user_credits(
    v_uid, v_creditos, 'devolucion_cancelacion',
    (v_ahora + interval '60 days')::text, 'Devolución — ' || v_nombre);
end if;
```

**Son ~35 líneas de cambio real** repartidas en 1 columna + 4 funciones
(`consume_user_credits_detallado` nueva, `reservar_clase`,
`confirm_pre_reserva`, `cancelar_mi_reserva`).

---

## Decisiones a tomar ANTES de escribir el código

1. **Si el lote original ya venció cuando cancelás, ¿se revive?**
   - *Estricto* (recomendado): se devuelve igual al lote, que sigue vencido ⇒ el
     crédito no revive. Es lo correcto: iba a vencer de todos modos.
   - *Generoso*: si todos los lotes de la reserva vencieron, dar un lote nuevo
     con N días. **Ojo: reabre el farmeo** justo en ese caso.
   Es la misma decisión que dejó abierta `BUILD22_cancelacion_flexible.md`.

2. **`estudio_cancelar_clase`** (hoy da 90 días nuevos): se propone **NO
   tocarla**. Ahí cancela el estudio y la usuaria es la perjudicada; darle
   tiempo fresco es política coherente y no lo puede provocar el usuario.

3. **`delete-account`** también devuelve créditos antes de borrar la cuenta. Da
   igual el vencimiento (la cuenta desaparece), pero conviene revisarla para que
   no rompa si la columna existe.

---

## SUITE DE VERIFICACIÓN — las dos puntas, con ROLLBACK, midiendo efecto

Correr **antes** del cambio (para que la #1 y la #3 fallen y demuestren el bug)
y **después** (para que las 8 den verde).

| # | Prueba | Esperado después del fix |
|---|---|---|
| 1 | Lote que vence mañana → reservar → cancelar | devuelve venciendo **mañana**. **Antes: +60 días** |
| 2 | Loop de 3 vueltas (clases distintas) | el vencimiento **no se mueve** en ninguna |
| 3 | **El caso del 20→30**: lotes a 20 y 30 días, consumir del corto, dejar vencer el corto, cancelar después | los créditos vuelven al **lote del 20** (vencido) — **no** heredan el 30 |
| 4 | Multi-lote: consumo que abarca dos lotes (10 del corto + 20 del largo) | cada lote recupera **exactamente lo suyo**: +10 y +20 |
| 5 | **Devolución legítima**: cancelar dentro de la ventana | el **saldo vuelve** al valor previo. No se pierden créditos |
| 6 | Reserva **vieja** (`creditos_lotes` null) | sigue el camino anterior, no rompe |
| 7 | Fuera de la ventana de cancelación | `fuera_de_ventana`, **nada devuelto** |
| 8 | Estado del ledger al terminar | **sin filas nuevas** y montos originales |

La **1** y la **3** son las que demuestran que el agujero se cerró; la **5** es
la que garantiza que no se rompió la devolución real por cerrarlo. Sin la
corrida *antes* del cambio, un "no ganó días" también sería el resultado de un
harness roto.

### Fixture para la prueba #3 (la del 20→30)

```sql
begin;
-- lote corto que vence en 2 días y lote largo a 30
perform public.grant_user_credits(:uid, 18, 'pack',   (now()+interval '2 days')::date::text, 'corto');
perform public.grant_user_credits(:uid, 50, 'regalo', (now()+interval '30 days')::date::text, 'largo');
-- reservar (consume del corto, que vence primero)
-- ... adelantar el reloj: en vez de esperar, vencer el lote corto a mano:
update public.creditos_movimientos set expires_at = now() - interval '1 day'
 where user_id = :uid and meta->>'description' = 'corto';
-- cancelar y medir a qué lote volvieron los créditos
rollback;
```

---

## ✅ El SQL de arriba está VALIDADO contra la base

No es pseudocódigo. El 2026-08-21 se corrió el Paso 1 (columna) y el Paso 2
(función nueva) contra producción dentro de una transacción con `rollback`, más
una prueba de humo del Paso 4. Compila y hace lo que dice:

```
lotes iniciales              corto#52 = 10 (vence 23/08)   largo#53 = 50 (vence 20/09)
consumo de 30                {"ok":true,"lotes":[{"id":52,"taken":10},{"id":53,"taken":20}]}
saldos tras consumir         corto = 0    largo = 30
saldos tras devolver         corto = 10   largo = 50        <- exacto
vencimientos                 corto 23/08  largo 20/09       <- PRESERVADOS
```

Repartió bien entre dos lotes (tomó primero del que vence antes), devolvió a
cada uno exactamente lo suyo, y ninguna fecha se movió. La base quedó intacta
por el rollback.

## Estado

- **No aplicado.** Se decidió no hacer el parche a medias.
- El código actual sigue renovando a 60 días en cada cancelación.
- Todo el cambio es de base: **no requiere build ni pasar por las tiendas.**

</details>
