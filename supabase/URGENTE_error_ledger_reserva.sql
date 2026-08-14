-- AURA — URGENTE: P0001 "los créditos se ajustan solo por el ledger" al reservar
-- (2026-08-13). Solo LEE. No modifica nada.
--
-- El error lo tira el trigger que protege usuarios.creditos de escrituras
-- directas. Su guarda es:
--     if current_user not in ('authenticated', 'anon') then return new;
--     if new.creditos is distinct from old.creditos then raise ...
--
-- O sea que salta cuando se cumplen DOS cosas a la vez:
--   1. quien escribe es el cliente (authenticated/anon), y
--   2. el valor de creditos REALMENTE cambia.
--
-- Toda la cadena de reserva debería ser SECURITY DEFINER (y entonces
-- current_user sería el dueño de la función, no 'authenticated'):
--     reservar_clase -> consume_user_credits -> refresh_user_credit_balance
--                    -> update usuarios set creditos
--
-- Si el error apareció, alguno de esos eslabones NO es definer, o hay OTRO
-- camino que actualiza usuarios.creditos desde el cliente.


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 1) 🔑 LA CADENA: ¿son todas SECURITY DEFINER y de quién son?             │
-- └──────────────────────────────────────────────────────────────────────────┘
-- `es_definer` tiene que ser true en las cuatro. Si alguna da false, ahí está.
select p.proname,
       p.prosecdef                    as es_definer,
       pg_get_userbyid(p.proowner)    as dueño,
       pg_get_function_identity_arguments(p.oid) as firma
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('reservar_clase', 'apply_reservation',
                     'consume_user_credits', 'refresh_user_credit_balance',
                     'grant_user_credits')
 order by p.proname;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 2) 🔑 ¿QUIÉN MÁS ESCRIBE usuarios.creditos SIN ser definer?              │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Cualquier función que toque usuarios.creditos y NO sea definer va a chocar
-- con el trigger cuando la llame el cliente. Este es el sospechoso principal.
select p.proname,
       p.prosecdef as es_definer,
       pg_get_function_identity_arguments(p.oid) as firma
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.prosrc ~* 'update\s+(public\.)?usuarios'
   and p.prosrc ~* 'creditos'
 order by p.prosecdef, p.proname;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 3) ¿Hay triggers nuevos o inesperados en las tablas del flujo?           │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Un trigger sobre `reservas` o `creditos_movimientos` que recalcule el saldo
-- correría en el contexto del cliente y explicaría el error.
select c.relname as tabla,
       t.tgname  as trigger,
       p.proname as funcion,
       p.prosecdef as funcion_es_definer
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  join pg_proc p on p.oid = t.tgfoid
 where n.nspname = 'public'
   and c.relname in ('usuarios', 'reservas', 'creditos_movimientos')
   and not t.tgisinternal
 order by c.relname, t.tgname;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 4) El trigger que tira el error, tal cual está hoy                       │
-- └──────────────────────────────────────────────────────────────────────────┘
select pg_get_functiondef(p.oid) as cuerpo
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname = 'usuarios_bloquear_columnas_sensibles';


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 5) EL CASO REAL: ¿la reserva de tu hermana se creó o no?                 │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Cambiá el mail. Importa saber si el error fue ANTES de reservar (no reservó
-- y no se le cobró) o DESPUÉS (reservó, se le cobró, y el error saltó al
-- refrescar el saldo).
select u.email,
       u.creditos                         as saldo_cacheado,
       coalesce(sum(m.amount_remaining), 0) as saldo_en_ledger,
       coalesce(sum(m.amount_remaining) filter (
         where m.expires_at is not null and m.expires_at::date < current_date
       ), 0)                              as vencidos_sin_limpiar
  from public.usuarios u
  left join public.creditos_movimientos m on m.user_id = u.id
 where u.email = 'PONE_ACA_EL_MAIL_DE_TU_HERMANA'
 group by u.id, u.email, u.creditos;

-- Sus reservas más recientes: si hay una de hoy, la reserva SÍ se creó.
select r.id, r.clase_id, r.estado, r.creditos_usados, r.created_at
  from public.reservas r
  join public.usuarios u on u.id = r.usuario_id
 where u.email = 'PONE_ACA_EL_MAIL_DE_TU_HERMANA'
 order by r.created_at desc
 limit 5;
