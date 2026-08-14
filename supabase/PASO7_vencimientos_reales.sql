-- ============================================================================
-- AURA — PASO 7: ¿los créditos vencen de verdad?
-- ============================================================================
-- TODO SOLO LECTURA.
--
-- Hasta ahora confirmamos que el NÚMERO correcto de días llega a la base.
-- Esto es otra cosa: que cuando esa fecha pasa, los créditos efectivamente
-- dejen de servir. Son dos cosas distintas.


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 7A — El estado real del ledger, movimiento por movimiento                │
-- └──────────────────────────────────────────────────────────────────────────┘
select u.email,
       m.source,
       m.amount_total      as se_acreditaron,
       m.amount_remaining  as quedan,
       m.expires_at        as vence,
       case
         when m.expires_at is null                then 'sin vencimiento'
         when m.expires_at < current_date         then '⛔ YA VENCIÓ'
         else '✅ vigente (' || (m.expires_at - current_date) || ' días)'
       end as estado,
       m.created_at::date  as se_acredito_el
  from public.creditos_movimientos m
  join public.usuarios u on u.id = m.user_id
 where m.amount_remaining > 0
 order by u.email, m.expires_at nulls last;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 7B — ⚠️ LA PRUEBA DE FUEGO                                               │
-- └──────────────────────────────────────────────────────────────────────────┘
-- El saldo que ve el usuario (usuarios.creditos) ¿excluye lo vencido?
--
-- Si alguna fila dice "🔴", hay créditos vencidos que el usuario todavía
-- puede gastar, o al revés: saldo que perdió sin que venciera nada.

select u.email,
       u.creditos as saldo_que_ve,
       coalesce(sum(m.amount_remaining) filter (
         where m.expires_at is null or m.expires_at >= current_date
       ), 0) as deberia_tener,
       coalesce(sum(m.amount_remaining) filter (
         where m.expires_at < current_date
       ), 0) as vencidos_sin_descontar,
       case
         when u.creditos = coalesce(sum(m.amount_remaining) filter (
                where m.expires_at is null or m.expires_at >= current_date
              ), 0)
           then '✅ coincide'
         else '🔴 NO COINCIDE'
       end as estado
  from public.usuarios u
  left join public.creditos_movimientos m on m.user_id = u.id
 group by u.id, u.email, u.creditos
having u.creditos <> 0
    or exists (select 1 from public.creditos_movimientos x
                where x.user_id = u.id and x.amount_remaining > 0)
 order by u.email;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 7C — ¿El consumo filtra vencidos, y gasta primero lo que vence antes?    │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Dos cosas que hay que ver en el cuerpo de consume_user_credits:
--   1. que ignore los movimientos con expires_at < hoy  (si no, gastás
--      créditos vencidos y el saldo miente)
--   2. que ordene por expires_at ASC  (si no, gasta primero los de larga
--      duración y deja vencer los cortos: la persona pierde créditos que
--      podría haber usado)

select p.proname,
       case when pg_get_functiondef(p.oid) ~* 'expires_at\s*(is null|>=|>)'
            then '✅ filtra vencidos' else '🔴 NO filtra vencidos' end as filtro,
       case when pg_get_functiondef(p.oid) ~* 'order by[^;]*expires_at'
            then '✅ ordena por vencimiento' else '⚠️ no ordena por vencimiento' end as orden
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('consume_user_credits', 'refresh_user_credit_balance')
 order by p.proname;


-- Y el cuerpo completo, para leerlo con mis propios ojos:
select p.proname, pg_get_functiondef(p.oid) as cuerpo
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('consume_user_credits', 'refresh_user_credit_balance')
 order by p.proname;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 7D — ¿Hay algo que limpie los vencidos, o se limpian al leer?            │
-- └──────────────────────────────────────────────────────────────────────────┘
select jobname, schedule, command
  from cron.job
 order by jobname;
