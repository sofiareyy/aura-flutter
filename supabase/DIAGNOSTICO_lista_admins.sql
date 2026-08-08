-- AURA — Diagnóstico: por qué no se ven todos los administradores (2026-08-07).
-- Solo LEE. No modifica nada.
--
-- Contexto: la data en estudio_admins está bien, pero las listas del backoffice
-- y del panel del estudio muestran de menos. Estas consultas identifican dónde
-- se pierden las filas.


-- 1) ¿Qué funciones de listado existen y qué hacen por dentro?
--    `admin_list_studio_accesses` NO está versionada en el repo (se creó desde
--    el dashboard), así que necesito ver su cuerpo para saber si filtra de más.
select p.proname                    as funcion,
       pg_get_function_identity_arguments(p.oid) as argumentos,
       p.prosecdef                  as es_security_definer,
       pg_get_functiondef(p.oid)    as definicion_completa
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in (
     'admin_list_studio_accesses',
     'admin_list_studio_members',
     'studio_list_profes'
   )
 order by p.proname;


-- 2) Policies de lectura sobre estudio_admins.
--    Si la única de SELECT es "usuario_id = auth.uid()", cualquier consulta
--    directa desde la app devuelve SOLO la fila del que consulta.
select policyname,
       cmd,
       roles,
       qual        as condicion_using,
       with_check  as condicion_with_check
  from pg_policies
 where schemaname = 'public'
   and tablename = 'estudio_admins'
 order by cmd, policyname;


-- 3) ¿Hay vínculos en estudio_admins cuyo usuario NO existe en public.usuarios?
--    Todas las funciones de listado hacen INNER JOIN contra usuarios, así que
--    estas filas se caen de la lista aunque el permiso exista.
--    Si devuelve 0 filas, descartamos esta causa.
select ea.estudio_id,
       e.nombre as estudio,
       ea.usuario_id,
       ea.rol,
       (au.id is not null) as existe_en_auth_users
  from public.estudio_admins ea
  left join public.usuarios e2 on e2.id = ea.usuario_id
  left join public.estudios e  on e.id  = ea.estudio_id
  left join auth.users au      on au.id = ea.usuario_id
 where e2.id is null
 order by ea.estudio_id;


-- 4) La verdad de la tabla: todos los vínculos, con nombre y mail.
--    Esta es la lista COMPLETA contra la que hay que comparar lo que muestra
--    cada pantalla.
select e.id   as estudio_id,
       e.nombre as estudio,
       ea.rol,
       u.nombre,
       u.email,
       ea.usuario_id
  from public.estudio_admins ea
  join public.estudios e on e.id = ea.estudio_id
  left join public.usuarios u on u.id = ea.usuario_id
 order by e.nombre,
          case ea.rol when 'estudio' then 0 when 'admin_estudio' then 1 else 2 end,
          u.email;


-- 5) Resumen por estudio: cuántos vínculos hay de cada rol.
--    Comparalo con lo que ves en pantalla para saber cuántos faltan.
select e.nombre as estudio,
       count(*) filter (where ea.rol = 'estudio')        as duenas,
       count(*) filter (where ea.rol = 'admin_estudio')  as admins,
       count(*) filter (where ea.rol = 'profe')          as profes,
       count(*)                                          as total
  from public.estudio_admins ea
  join public.estudios e on e.id = ea.estudio_id
 group by e.nombre
 order by e.nombre;
