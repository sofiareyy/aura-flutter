-- AURA - V2 del fix de RLS para que el estudio pueda leer / actualizar
-- reservas de SUS clases (2026-06-12).
--
-- En la V1 (FIX_RLS_RESERVAS_ESTUDIO.sql) la policy solo cubria el camino
-- nuevo: usuario presente en public.estudio_admins. Si el usuario sigue
-- vinculado al estudio por el camino legacy (public.usuarios.estudio_id)
-- pero NO esta en estudio_admins, el QR no se encuentra y aparece
-- "QR invalido" aunque la reserva exista y los creditos esten descontados.
--
-- Esta V2 reemplaza las dos policies con versiones que aceptan AMBOS
-- caminos. Es idempotente: drop if exists + recreate.


-- 1. SELECT — estudio admin lee reservas de sus clases (via estudio_admins
--    O via usuarios.estudio_id como fallback). ---------------------------

drop policy if exists "estudio lee reservas de sus clases" on public.reservas;
create policy "estudio lee reservas de sus clases"
  on public.reservas for select
  using (
    exists (
      select 1
        from public.clases c
       where c.id = reservas.clase_id
         and (
           c.estudio_id in (
             select estudio_id
               from public.estudio_admins
              where usuario_id = auth.uid()
           )
           or
           c.estudio_id = (
             select estudio_id
               from public.usuarios
              where id = auth.uid()
           )
         )
    )
  );


-- 2. UPDATE — estudio admin actualiza estado / checked_in_at. ------------

drop policy if exists "estudio actualiza reservas de sus clases" on public.reservas;
create policy "estudio actualiza reservas de sus clases"
  on public.reservas for update
  using (
    exists (
      select 1
        from public.clases c
       where c.id = reservas.clase_id
         and (
           c.estudio_id in (
             select estudio_id
               from public.estudio_admins
              where usuario_id = auth.uid()
           )
           or
           c.estudio_id = (
             select estudio_id
               from public.usuarios
              where id = auth.uid()
           )
         )
    )
  )
  with check (
    exists (
      select 1
        from public.clases c
       where c.id = reservas.clase_id
         and (
           c.estudio_id in (
             select estudio_id
               from public.estudio_admins
              where usuario_id = auth.uid()
           )
           or
           c.estudio_id = (
             select estudio_id
               from public.usuarios
              where id = auth.uid()
           )
         )
    )
  );


-- 3. DIAGNOSTICO — policies vigentes en reservas. -----------------------

select policyname, cmd, qual
  from pg_policies
 where schemaname = 'public'
   and tablename = 'reservas'
 order by policyname;


-- 4. DIAGNOSTICO — ultimas 5 reservas. ---------------------------------

select codigo_qr, estado, clase_id, usuario_id, created_at
  from public.reservas
 order by created_at desc
 limit 5;


-- 5. DIAGNOSTICO — buscar la reserva problematica exacta. --------------
-- Esto deberia devolver 1 fila. Si devuelve 0 desde la consola SQL del
-- proyecto (que corre como service_role bypass), el codigo_qr no existe
-- en DB (problema de generacion). Si devuelve 1, el problema es la app
-- (RLS o normalizacion).

select id, codigo_qr, estado, clase_id, usuario_id, created_at
  from public.reservas
 where codigo_qr = 'AURA-02D233DE-305-1781291369795-5309';


-- 6. DIAGNOSTICO — vinculo del usuario actual con el estudio. ----------
-- Correr esto LOGUEADO COMO EL ESTUDIO (ej. desde la app via RPC o
-- desde el SQL Editor con "Run as user" si esta soportado). En SQL Editor
-- normal auth.uid() es null y devuelve vacio.

select
  auth.uid()                                                  as actual_uid,
  (select estudio_id from public.usuarios   where id = auth.uid()) as legacy_estudio_id,
  array(
    select estudio_id from public.estudio_admins where usuario_id = auth.uid()
  )                                                           as estudio_admins_ids;
