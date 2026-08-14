-- ============================================================================
-- AURA — PASO 8: necesito el cuerpo actual de grant_user_credits
-- ============================================================================
-- SOLO LECTURA.
--
-- grant_user_credits no está en ninguna migración (la creaste desde el
-- dashboard), así que no puedo reescribirla sin ver exactamente cómo está
-- hoy. Pasame el resultado y con eso escribo el arreglo.

select p.proname,
       pg_get_function_identity_arguments(p.oid) as argumentos,
       pg_get_functiondef(p.oid)                 as cuerpo
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname = 'grant_user_credits';


-- Y esto para saber quién puede ejecutarla (D1 revocó permisos, quiero
-- respetar lo mismo en la función nueva):
select p.proname,
       p.prosecdef as security_definer,
       coalesce(array_to_string(p.proacl, ' | '), 'sin ACL explícita') as permisos
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('grant_user_credits', 'consume_user_credits')
 order by p.proname;
