-- AURA — URGENTE: por qué falla la reserva (2026-08-13). Solo LEE.
--
-- El log muestra esta secuencia, tres veces seguidas:
--     42501  permission denied for function consume_user_credits
--     P0001  Los creditos se ajustan solo por el ledger
--
-- El 42501 va PRIMERO: el error de raíz es de permisos, no del ledger.
-- El P0001 es la consecuencia de que algo intente descontar por otro camino.

-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 1) 🔑 EL CUERPO REAL de reservar_clase que está desplegado               │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Buscá si tiene un `exception when others` o un update directo sobre
-- usuarios.creditos como plan B cuando consume_user_credits falla.
select pg_get_functiondef(p.oid) as cuerpo
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname = 'reservar_clase';


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 2) 🔑 QUIÉN PUEDE EJECUTAR consume_user_credits                          │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Si no aparece ninguna fila, NADIE tiene permiso salvo el dueño. Y si
-- reservar_clase la llama en un contexto que no es el del dueño, revienta
-- con 42501, que es justo lo que muestra el log.
select p.proname,
       pg_get_userbyid(p.proowner) as dueño,
       p.prosecdef                 as es_definer,
       coalesce(array_to_string(p.proacl, ' | '), '(sin ACL: solo el dueño)') as permisos
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('consume_user_credits', 'reservar_clase',
                     'apply_reservation', 'refresh_user_credit_balance',
                     'grant_user_credits')
 order by p.proname;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 3) ¿Hay más de una versión de reservar_clase o de consume_user_credits?  │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Dos versiones conviviendo explicarían que el comportamiento no coincida
-- con el código de la migración.
select p.proname,
       count(*) as versiones,
       string_agg(pg_get_function_identity_arguments(p.oid), '  ||  ') as firmas
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('reservar_clase', 'consume_user_credits')
 group by p.proname;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 4) APARTE: otros dos errores que aparecen en el log                      │
-- └──────────────────────────────────────────────────────────────────────────┘
-- 42703 "column creditos_movimientos.usuario_id does not exist"
--   La columna real es `user_id`. Algo la consulta con el nombre equivocado.
-- 42702 "column reference estudio_id is ambiguous"
--   Un join sin calificar la columna.
-- No bloquean la reserva, pero son bugs reales. Esto los ubica.
select p.proname,
       pg_get_function_identity_arguments(p.oid) as firma,
       case
         when p.prosrc ~* 'creditos_movimientos[^;]*usuario_id' then 'usa usuario_id (mal)'
         else 'estudio_id sin calificar'
       end as problema
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and (p.prosrc ~* 'creditos_movimientos[^;]*usuario_id'
        or (p.prosrc ~* 'estudio_id' and p.prosrc ~* 'join'))
 order by p.proname;
