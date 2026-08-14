-- AURA — ¿El circuito pago → acreditación está sano? (2026-08-10). Solo LEE.
--
-- No simula un pago: audita los que YA pasaron y busca inconsistencias entre
-- lo pagado, el ledger de créditos y el saldo que ve el usuario.
--
-- Cómo funciona el circuito (para leer los resultados):
--   1. crear-checkout-pack   -> inserta `pagos` en status 'pending'
--   2. Mercado Pago aprueba  -> mp-webhook (o confirmar-pago-manual) llama a
--                               process_approved_pack_payment
--   3. Esa función           -> grant_user_credits (inserta en
--                               creditos_movimientos) y marca el pago con
--                               status='approved' + credits_granted_at=now()
--   4. usuarios.creditos     = SUMA de creditos_movimientos.amount_remaining
--                               (lo recalcula refresh_user_credit_balance)
--
-- La regla de oro: un pago aprobado SIEMPRE tiene credits_granted_at, y por
-- cada uno tiene que existir su movimiento en el ledger.


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 1) Foto de todos los pagos, por estado                                   │
-- └──────────────────────────────────────────────────────────────────────────┘
select type,
       status,
       count(*)                                          as cantidad,
       count(*) filter (where credits_granted_at is not null) as acreditados,
       sum(creditos)                                     as creditos_totales,
       min(created_at)                                   as primero,
       max(created_at)                                   as ultimo
  from public.pagos
 group by type, status
 order by type, status;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 2) 🔴 PAGOS APROBADOS SIN ACREDITAR — plata cobrada sin créditos dados   │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Es el caso más grave: el usuario pagó y no recibió nada.
-- Tiene que dar 0 filas.
select p.id, p.user_id, u.email, p.type, p.creditos, p.amount,
       p.mp_payment_id, p.created_at
  from public.pagos p
  left join public.usuarios u on u.id = p.user_id
 where p.status = 'approved'
   and p.credits_granted_at is null
 order by p.created_at desc;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 3) 🔴 PAGOS ACREDITADOS SIN MOVIMIENTO EN EL LEDGER                      │
-- └──────────────────────────────────────────────────────────────────────────┘
-- El pago dice que acreditó, pero no hay créditos en el ledger de ese usuario
-- cerca de esa fecha. Solo aplica a 'pack' (los 'gift' NO acreditan al
-- comprador: crean un regalo para que lo canjee otro).
-- Tiene que dar 0 filas.
select p.id, u.email, p.creditos as creditos_del_pago, p.credits_granted_at
  from public.pagos p
  left join public.usuarios u on u.id = p.user_id
 where p.type = 'pack'
   and p.credits_granted_at is not null
   and not exists (
     select 1 from public.creditos_movimientos m
      where m.user_id = p.user_id
        and m.source = 'pack'
        and m.amount_total = p.creditos
        and m.created_at between p.credits_granted_at - interval '5 minutes'
                             and p.credits_granted_at + interval '5 minutes'
   )
 order by p.credits_granted_at desc;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 4) 🔴 mp_payment_id DUPLICADO — riesgo de doble acreditación             │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Un mismo pago de Mercado Pago vinculado a dos filas de `pagos`.
-- Tiene que dar 0 filas.
select mp_payment_id, count(*) as veces, array_agg(id) as pago_ids
  from public.pagos
 where mp_payment_id is not null
 group by mp_payment_id
having count(*) > 1;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 5) 🔴 CONCILIACIÓN: saldo del usuario vs ledger                          │
-- └──────────────────────────────────────────────────────────────────────────┘
-- usuarios.creditos tiene que ser igual a la suma de amount_remaining.
-- Si difiere, alguien escribió el saldo por afuera del ledger.
-- Tiene que dar 0 filas.
select u.id, u.email,
       u.creditos                        as saldo_en_usuarios,
       coalesce(sum(m.amount_remaining), 0) as saldo_en_ledger,
       u.creditos - coalesce(sum(m.amount_remaining), 0) as diferencia
  from public.usuarios u
  left join public.creditos_movimientos m on m.user_id = u.id
 group by u.id, u.email, u.creditos
having u.creditos is distinct from coalesce(sum(m.amount_remaining), 0)
 order by abs(u.creditos - coalesce(sum(m.amount_remaining), 0)) desc;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 6) De dónde salieron todos los créditos que existen hoy                  │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Panorama sano: 'pack' (comprados), 'regalo', 'referido', 'manual' (ajustes
-- del backoffice), 'devolucion_clase_cancelada'. Si aparece un `source` raro
-- o 'manual' con mucho volumen, vale mirarlo.
select source,
       count(*)               as movimientos,
       sum(amount_total)      as creditos_otorgados,
       sum(amount_remaining)  as sin_usar_aun
  from public.creditos_movimientos
 group by source
 order by sum(amount_total) desc;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 7) Los últimos 20 pagos, para mirar a ojo                                │
-- └──────────────────────────────────────────────────────────────────────────┘
select p.created_at, u.email, p.type, p.status, p.amount, p.creditos,
       (p.credits_granted_at is not null) as acreditado,
       p.pack_nombre, p.gift_email
  from public.pagos p
  left join public.usuarios u on u.id = p.user_id
 order by p.created_at desc
 limit 20;
