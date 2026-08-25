-- ═══════════════════════════════════════════════════════════════════════════
-- FIX · Yessi Funes: dos grillas en el mismo slot (miércoles 18:00)
-- 2026-08-25 · confirmado por la dueña (va a reordenar sus clases igual)
--
-- No era un doble tap: eran dos grillas DISTINTAS en el mismo slot,
--   id 165  "Fumcional" / Natalia  · 13 clases · 0 reservas   → SE QUEDA
--   id 173  "Funcional" / Tomas    · 10 clases · 0 reservas   → SE BORRA
-- Criterio: queda la de menor id, como en la limpieza de Tiwar.
--
-- ⚠️ `clases.horario_fijo_id` es ON DELETE **SET NULL**, no CASCADE. Borrar
-- solo la grilla dejaria sus 10 clases huerfanas y publicadas: el duplicado
-- seguiria vivo como "clase suelta". Por eso se borran las clases PRIMERO y
-- explicitamente. Vale tambien para la limpieza de Tiwar.
--
-- Las 10 clases (19/08 al 21/10, mie 18:00) tienen 0 reservas en cualquier
-- estado, asi que `trg_clases_bloquear_borrado` no interviene. Se borra
-- tambien la del 19/08 (pasada): es un duplicado sin asistencia, no historia.
-- ═══════════════════════════════════════════════════════════════════════════
do $$
declare v_res int; v_cl int;
begin
  select count(*) into v_res from public.reservas r join public.clases c on c.id=r.clase_id where c.horario_fijo_id = 173;
  if v_res <> 0 then raise exception 'ABORT: la grilla 173 tiene % reservas, revisar a mano', v_res; end if;
  if not exists (select 1 from public.horarios_fijos where id=165 and estudio_id=10 and dia_semana=3 and hora_inicio='18:00') then
    raise exception 'ABORT: la grilla 165 no es la esperada'; end if;
  if not exists (select 1 from public.horarios_fijos where id=173 and estudio_id=10 and dia_semana=3 and hora_inicio='18:00') then
    raise exception 'ABORT: la grilla 173 no es la esperada'; end if;

  delete from public.clases where horario_fijo_id = 173;
  get diagnostics v_cl = row_count;
  delete from public.horarios_fijos where id = 173;
  raise notice 'borradas % clases y la grilla 173', v_cl;
end $$;
