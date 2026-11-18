-- Kumaly (18/11/2026, tercera parte): la ocupación busca la clase por
-- estudio + hora y la SALA sólo desempata. Decisión de la usuaria:
--   · una sola clase vigente del estudio a esa hora → es esa, sin mirar sala;
--   · dos o más → la sala (sin mayúsculas ni espacios de más) desempata; si
--     ninguna coincide, 404; si coinciden varias, 409 clase_ambigua;
--   · las canceladas no cuentan si hay alguna vigente; si a esa hora sólo
--     hay canceladas, 200 sin tocar nada (ya_cancelada / ignorado).
-- Sólo cambia _kumaly_ocupacion; los permisos de la función se conservan.

create or replace function public._kumaly_ocupacion(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_estudio    bigint;
  v_inicio     timestamptz;
  v_fecha      timestamp;
  v_sala       text;
  v_ids        bigint[];
  v_clase      public.clases%rowtype;
  v_ahora      timestamp := (now() at time zone 'America/Argentina/Buenos_Aires');
  v_ocupados   int;
  v_pendientes int;
  v_libres     int;
  v_cancelacion jsonb;
begin
  if jsonb_typeof(p->'estudio_id') is distinct from 'number' then
    return jsonb_build_object('http', 400, 'error', 'falta_estudio_id');
  end if;
  v_estudio := (p->>'estudio_id')::bigint;
  if not public._kumaly_activo(v_estudio) then
    return jsonb_build_object('http', 403, 'error', 'estudio_no_integrado');
  end if;

  v_inicio := public._kumaly_parse_iso(p->>'inicio');
  if v_inicio is null then
    return jsonb_build_object('http', 400, 'error', 'inicio_invalido',
      'detalle', 'ISO 8601 con el huso escrito, por ejemplo 2026-11-19T18:00:00-03:00');
  end if;
  v_fecha := v_inicio at time zone 'America/Argentina/Buenos_Aires';
  v_sala := public._kumaly_sala(p->>'sala');

  -- Candidatas: las clases del estudio a esa hora. Primero las vigentes; si
  -- no hay ninguna, las canceladas (así un cancelada:true repetido sigue
  -- contestando ya_cancelada).
  select array_agg(c.id order by c.id) into v_ids
    from public.clases c
   where c.estudio_id = v_estudio
     and c.fecha = v_fecha
     and not coalesce(c.cancelada, false);
  if v_ids is null then
    select array_agg(c.id order by c.id) into v_ids
      from public.clases c
     where c.estudio_id = v_estudio
       and c.fecha = v_fecha;
    -- A esa hora sólo hay clases canceladas: no hay nada que tocar.
    if v_ids is not null then
      if coalesce((p->>'cancelada')::boolean, false) then
        return jsonb_build_object('http', 200, 'ok', true, 'clases', v_ids, 'ya_cancelada', true);
      end if;
      return jsonb_build_object('http', 200, 'ok', true, 'clases', v_ids,
                                'ignorado', 'clase_cancelada');
    end if;
  end if;

  if v_ids is null then
    return jsonb_build_object('http', 404, 'error', 'clase_no_encontrada',
      'fecha', v_fecha, 'sala', p->>'sala');
  end if;

  -- Una sola a esa hora: es esa, diga lo que diga la sala (18/11: así no
  -- dependemos de que el estudio escriba el nombre igual que su sistema de
  -- turnos). Dos o más: la sala desempata.
  if array_length(v_ids, 1) > 1 then
    select array_agg(c.id order by c.id) into v_ids
      from public.clases c
     where c.id = any(v_ids)
       and public._kumaly_sala(c.sala) is not distinct from v_sala;
    if v_ids is null then
      return jsonb_build_object('http', 404, 'error', 'clase_no_encontrada',
        'fecha', v_fecha, 'sala', p->>'sala',
        'detalle', 'hay varias clases a esa hora y ninguna tiene esa sala');
    end if;
    if array_length(v_ids, 1) > 1 then
      return jsonb_build_object('http', 409, 'error', 'clase_ambigua', 'clases', v_ids);
    end if;
  end if;

  select * into v_clase from public.clases where id = v_ids[1] for update;

  -- Clase suspendida por el estudio.
  if coalesce((p->>'cancelada')::boolean, false) then
    if coalesce(v_clase.cancelada, false) then
      return jsonb_build_object('http', 200, 'ok', true, 'clase_id', v_clase.id, 'ya_cancelada', true);
    end if;
    if v_clase.fecha <= v_ahora then
      return jsonb_build_object('http', 422, 'error', 'clase_ya_empezo', 'clase_id', v_clase.id);
    end if;
    perform set_config('aura.origen', 'kumaly', true);
    v_cancelacion := public._cancelar_clase_y_devolver(v_clase.id);
    perform set_config('aura.origen', '', true);
    return jsonb_build_object('http', 200, 'clase_id', v_clase.id) || v_cancelacion;
  end if;

  if jsonb_typeof(p->'ocupados') is distinct from 'number'
     or (p->>'ocupados')::numeric <> floor((p->>'ocupados')::numeric)
     or (p->>'ocupados')::numeric < 0 then
    return jsonb_build_object('http', 400, 'error', 'ocupados_invalido');
  end if;
  v_ocupados := (p->>'ocupados')::int;

  if coalesce(v_clase.cancelada, false) then
    return jsonb_build_object('http', 200, 'ok', true, 'clase_id', v_clase.id,
                              'ignorado', 'clase_cancelada');
  end if;

  -- Nuestras reservas que Kumaly todavía no confirmó: no están en su total.
  select count(*) into v_pendientes
    from public.reservas r
    join public.kumaly_envios e
      on e.reserva_id = r.id and e.evento = 'reserva' and e.estado = 'pendiente'
   where r.clase_id = v_clase.id and r.estado = 'confirmada';

  v_libres := greatest(0, coalesce(v_clase.lugares_total, 0)::int - v_ocupados - v_pendientes);
  update public.clases set lugares_disponibles = v_libres where id = v_clase.id;

  return jsonb_build_object('http', 200, 'ok', true, 'clase_id', v_clase.id,
    'lugares_total', v_clase.lugares_total, 'ocupados', v_ocupados,
    'pendientes', v_pendientes, 'lugares_disponibles', v_libres);
end;
$function$;

