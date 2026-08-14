-- AURA — ¿Los créditos vencen de verdad? (2026-08-13). Solo LEE.
--
-- La fecha de vencimiento SÍ se guarda: grant_user_credits escribe
-- creditos_movimientos.expires_at al acreditar un pack.
--
-- Lo que NO se puede saber desde el repo es si esa fecha se respeta, porque
-- las dos funciones que deciden el saldo se crearon desde el dashboard y su
-- código no está versionado:
--     refresh_user_credit_balance  -> calcula usuarios.creditos
--     consume_user_credits         -> descuenta al reservar
--
-- Estas consultas responden las dos cosas: qué dicen esas funciones, y qué
-- pasa con los datos reales.


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 1) 🔑 LA CLAVE: ¿esas funciones filtran por expires_at?                  │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Si `filtra_vencimiento` da TRUE en las dos, los créditos vencen de verdad
-- (se respetan al leer el saldo y al gastarlo). Si da FALSE, la fecha se
-- guarda pero no la mira nadie.
select p.proname,
       (p.prosrc ilike '%expires_at%') as filtra_vencimiento,
       pg_get_functiondef(p.oid)       as cuerpo
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('refresh_user_credit_balance', 'consume_user_credits')
 order by p.proname;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 2) ¿Hay algún cron que expire créditos?                                  │
-- └──────────────────────────────────────────────────────────────────────────┘
-- En el repo no hay ninguno. Puede estar bien (lo normal es filtrar al leer,
-- no correr un batch), pero conviene confirmar qué hay agendado.
select jobname, schedule, active, command
  from cron.job
 order by jobname;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 3) 🔴 LA PRUEBA CON DATOS REALES                                         │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Por cada usuario: cuántos créditos tiene vigentes y cuántos vencidos.
--
-- Leerlo así:
--   * saldo_visible == vigentes            -> el vencimiento SE RESPETA ✅
--   * saldo_visible == vigentes + vencidos -> está mostrando créditos que
--                                             ya deberían haber expirado 🔴
select u.email,
       u.creditos                                   as saldo_visible,
       u.creditos_vencimiento                       as vence_el,
       coalesce(sum(m.amount_remaining) filter (
         where m.expires_at is null
            or m.expires_at::date >= current_date
       ), 0)                                        as vigentes,
       coalesce(sum(m.amount_remaining) filter (
         where m.expires_at is not null
           and m.expires_at::date < current_date
       ), 0)                                        as vencidos,
       case
         when coalesce(sum(m.amount_remaining) filter (
                where m.expires_at is not null
                  and m.expires_at::date < current_date
              ), 0) = 0
           then 'sin vencidos'
         when u.creditos = coalesce(sum(m.amount_remaining) filter (
                where m.expires_at is null
                   or m.expires_at::date >= current_date
              ), 0)
           then '✅ el saldo ya los descuenta'
         else '🔴 el saldo INCLUYE créditos vencidos'
       end                                          as veredicto
  from public.usuarios u
  join public.creditos_movimientos m on m.user_id = u.id
 group by u.id, u.email, u.creditos, u.creditos_vencimiento
having coalesce(sum(m.amount_remaining), 0) > 0
 order by vencidos desc, u.email;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 4) Resumen: cuántos créditos vencidos hay dando vueltas                  │
-- └──────────────────────────────────────────────────────────────────────────┘
select count(*)                    as movimientos_vencidos_con_saldo,
       sum(amount_remaining)       as creditos_vencidos_sin_usar,
       min(expires_at)             as el_mas_viejo,
       max(expires_at)             as el_mas_reciente
  from public.creditos_movimientos
 where expires_at is not null
   and expires_at::date < current_date
   and amount_remaining > 0;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 5) ¿Se están guardando las fechas al acreditar?                          │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Los movimientos de 'pack' deberían tener expires_at siempre. Un 'manual'
-- sin fecha es esperable (los ajustes del backoffice no vencen).
select source,
       count(*)                                           as movimientos,
       count(*) filter (where expires_at is null)         as sin_vencimiento,
       count(*) filter (where expires_at is not null)     as con_vencimiento
  from public.creditos_movimientos
 group by source
 order by source;
