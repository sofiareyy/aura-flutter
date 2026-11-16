-- 16/11/2026 · "Guardar precios" dice qué recalculó (pedido de Sofía).
--
-- admin_recalcular_precios_estudio devolvía un solo número: TODAS las clases
-- que pudo calcular, hayan cambiado o no (Citra: 625, pasadas incluidas), y la
-- pantalla tragaba cualquier error y decía "Configuración guardada".
--
-- La _detalle hace exactamente el mismo recálculo pero cuenta lo que pasó de
-- verdad: cuántas clases cambiaron de precio, cuántas quedaron igual, cuántas
-- de las que cambiaron ya tenían reservas (a esas alumnas NO se les cobra la
-- diferencia: lo que se liquida sale de reservas.creditos_usados), y cuántos
-- horarios fijos cambiaron. El panel la llama con p_incluir_pasadas = false.
--
-- La vieja queda como está (la usan otras pantallas). Rollback:
--   drop function public.admin_recalcular_precios_estudio_detalle(bigint, boolean);

create or replace function public.admin_recalcular_precios_estudio_detalle(
  p_estudio_id bigint,
  p_incluir_pasadas boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_clase      record;
  v_res        json;
  v_serv       record;
  v_desde      timestamp;
  v_nuevo      int;
  v_cambiadas  int := 0;
  v_iguales    int := 0;
  v_sin_precio int := 0;
  v_con_res    int := 0;
  v_horarios   int := 0;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  v_desde := case
    when p_incluir_pasadas then '-infinity'::timestamp
    else (timezone('America/Argentina/Buenos_Aires', now()))::date::timestamp
  end;

  for v_clase in
    select c.id, c.estudio_id, c.fecha, c.categorias, c.creditos, c.tipo_precio,
           exists (select 1 from public.reservas r
                    where r.clase_id = c.id
                      and r.estado in ('confirmada', 'pre_confirmada', 'presente')) as tiene_reservas
      from public.clases c
     where c.estudio_id = p_estudio_id
       and coalesce(c.tipo, 'clase') <> 'workshop'
       and (c.fecha)::timestamp >= v_desde
  loop
    begin
      select * into v_serv
        from public.servicio_precio_fijo(v_clase.estudio_id, v_clase.categorias);
    exception when others then
      v_serv := null;
    end;

    v_res := public.calcular_precio_clase(
      v_clase.estudio_id, v_serv.servicio,
      extract(isodow from v_clase.fecha)::int,
      to_char(v_clase.fecha, 'HH24:MI')
    );
    if not coalesce((v_res ->> 'ok')::boolean, false) then
      v_sin_precio := v_sin_precio + 1;
      continue;
    end if;

    v_nuevo := (v_res ->> 'creditos')::int;
    if v_nuevo is distinct from v_clase.creditos
       or (v_res ->> 'tipo') is distinct from v_clase.tipo_precio then
      update public.clases
         set creditos    = v_nuevo,
             tipo_precio = v_res ->> 'tipo'
       where id = v_clase.id;
      v_cambiadas := v_cambiadas + 1;
      if v_clase.tiene_reservas then v_con_res := v_con_res + 1; end if;
    else
      v_iguales := v_iguales + 1;
    end if;
  end loop;

  with calc as (
    select hf.id,
           public.calcular_precio_clase(
             hf.estudio_id,
             (select s.servicio from public.servicio_precio_fijo(hf.estudio_id, hf.categorias) s limit 1),
             hf.dia_semana, to_char(hf.hora_inicio, 'HH24:MI')
           ) as res
      from public.horarios_fijos hf
     where hf.estudio_id = p_estudio_id
  ), upd as (
    update public.horarios_fijos h
       set creditos = (calc.res ->> 'creditos')::int
      from calc
     where h.id = calc.id
       and coalesce(to_jsonb(h) ->> 'tipo', 'clase') <> 'workshop'
       and coalesce((calc.res ->> 'ok')::boolean, false)
       and h.creditos is distinct from (calc.res ->> 'creditos')::int
    returning 1
  )
  select count(*) into v_horarios from upd;

  perform public.log_admin_action(
    'Recalcular precios',
    'Estudio #' || p_estudio_id || ': ' || v_cambiadas || ' clases cambiaron, '
      || v_iguales || ' iguales, ' || v_horarios || ' horarios',
    'estudios');

  return jsonb_build_object(
    'cambiadas', v_cambiadas,
    'iguales', v_iguales,
    'sin_precio', v_sin_precio,
    'cambiadas_con_reservas', v_con_res,
    'horarios_cambiados', v_horarios,
    'desde', case when p_incluir_pasadas then null else v_desde::date end
  );
end;
$function$;

revoke all on function public.admin_recalcular_precios_estudio_detalle(bigint, boolean) from public, anon;
grant execute on function public.admin_recalcular_precios_estudio_detalle(bigint, boolean) to authenticated;
