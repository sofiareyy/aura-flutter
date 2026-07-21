-- ============================================================================
-- Fix: completar_reservas_vencidas fallaba por tipo (bigint vs int)
-- ============================================================================
--
-- El cron 'completar-reservas' venía fallando cada hora con:
--   function make_interval(mins => bigint) does not exist
--
-- `clases.duracion_min` es bigint y make_interval espera int. El estado
-- 'completada' no se estaba escribiendo (justo lo que buscaba FIX 8). Se
-- castea a int. Idéntica a la versión de TANDA_A salvo el `::int`.
-- ============================================================================

create or replace function public.completar_reservas_vencidas()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ahora timestamp := (
    now() at time zone 'America/Argentina/Buenos_Aires'
  );
  v_gracia interval := interval '3 hours';
  v_completadas int := 0;
begin
  with vencidas as (
    select r.id
      from public.reservas r
      join public.clases c on c.id = r.clase_id
     where r.estado in ('confirmada', 'presente')
       and c.fecha is not null
       and c.fecha
           + make_interval(mins => coalesce(c.duracion_min, 60)::int)
           + v_gracia
           < v_ahora
  )
  update public.reservas r
     set estado = 'completada'
    from vencidas v
   where r.id = v.id;

  get diagnostics v_completadas = row_count;

  return json_build_object(
    'completadas', v_completadas,
    'corrido_a', v_ahora,
    'gracia_horas', 3
  );
end;
$$;

grant execute on function public.completar_reservas_vencidas() to service_role;
