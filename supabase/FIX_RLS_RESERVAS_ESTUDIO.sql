-- AURA - Permitir que los administradores del estudio lean / actualicen
-- reservas de SUS clases (2026-06-11).
--
-- Bug: al escanear el QR en AsistenciaScreen el panel decia "QR invalido"
-- aunque la reserva existia y el usuario tenia los creditos descontados.
-- Causa: las policies de reservas dejaban leer solo las reservas propias
-- (usuario_id = auth.uid()), asi que cuando el estudio buscaba por
-- codigo_qr no encontraba la fila — no era el dueno de la reserva, era
-- el dueno de la clase.
--
-- Estas policies son aditivas: no tocan el acceso del usuario a sus
-- propias reservas (siguen funcionando las policies existentes), solo
-- agregan acceso del admin de estudio a las reservas de sus clases via
-- estudio_admins.


-- 1. SELECT: estudio admin puede leer reservas de sus clases ----------

drop policy if exists "estudio lee reservas de sus clases" on public.reservas;
create policy "estudio lee reservas de sus clases"
  on public.reservas for select
  using (
    exists (
      select 1
        from public.clases c
        join public.estudio_admins ea on ea.estudio_id = c.estudio_id
       where c.id = reservas.clase_id
         and ea.usuario_id = auth.uid()
    )
  );


-- 2. UPDATE: estudio admin puede marcar 'presente' / 'ausente' /
--    'cancelada_por_estudio' al hacer check-in con QR -----------------

drop policy if exists "estudio actualiza reservas de sus clases" on public.reservas;
create policy "estudio actualiza reservas de sus clases"
  on public.reservas for update
  using (
    exists (
      select 1
        from public.clases c
        join public.estudio_admins ea on ea.estudio_id = c.estudio_id
       where c.id = reservas.clase_id
         and ea.usuario_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
        from public.clases c
        join public.estudio_admins ea on ea.estudio_id = c.estudio_id
       where c.id = reservas.clase_id
         and ea.usuario_id = auth.uid()
    )
  );


-- 3. Diagnostico — ultimas 5 reservas (segun pedido del bug) ----------

select codigo_qr, estado, clase_id, created_at
  from public.reservas
 order by created_at desc
 limit 5;


-- 4. Diagnostico extra — policies vigentes en reservas ----------------
-- Confirmar que las dos nuevas policies aparecen y que el SELECT del
-- usuario sigue presente.

select tablename, policyname, cmd, qual
  from pg_policies
 where schemaname = 'public'
   and tablename = 'reservas'
 order by policyname;
