-- Kumaly (19/11/2026): ajustes antes de la prueba con su lado.
--  · Números que pueden venir como texto: estudio_id ("70"), reserva_id y
--    ocupados se aceptan como número o como texto de sólo dígitos.
--  · Una cancelación que Kumaly contesta 404 (no tiene esa reserva) se da por
--    resuelta, sin reintentar.
-- Nuestros códigos hacia Kumaly: 2xx = anotado (también si es repetido);
-- 4xx = definitivo, no reintentar; 5xx = error nuestro, reintentar.

create or replace function public._kumaly_entero(p_valor jsonb)
returns bigint
language sql
immutable
as $$
  select case
    when jsonb_typeof(p_valor) = 'number'
         and (p_valor #>> '{}')::numeric = floor((p_valor #>> '{}')::numeric)
      then (p_valor #>> '{}')::numeric::bigint
    when jsonb_typeof(p_valor) = 'string' and btrim(p_valor #>> '{}') ~ '^-?[0-9]{1,18}$'
      then btrim(p_valor #>> '{}')::bigint
  end
$$;

CREATE OR REPLACE FUNCTION public._kumaly_ocupacion(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  v_estudio := public._kumaly_entero(p->'estudio_id');
  if v_estudio is null then
    return jsonb_build_object('http', 400, 'error', 'falta_estudio_id');
  end if;
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

  if public._kumaly_entero(p->'ocupados') is null
     or public._kumaly_entero(p->'ocupados') < 0 then
    return jsonb_build_object('http', 400, 'error', 'ocupados_invalido');
  end if;
  v_ocupados := public._kumaly_entero(p->'ocupados')::int;

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

CREATE OR REPLACE FUNCTION public._kumaly_asistencia(p jsonb, p_recibido timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_r       public.reservas%rowtype;
  v_clase   public.clases%rowtype;
  v_estudio public.estudios%rowtype;
  v_ahora   timestamp := (p_recibido at time zone 'America/Argentina/Buenos_Aires');
  v_marcado timestamptz;
  v_ultimo  timestamptz;
  v_nuevo   text;
  v_desde   timestamp;
  v_hasta   timestamp;
begin
  if public._kumaly_entero(p->'reserva_id') is null then
    return jsonb_build_object('http', 400, 'error', 'falta_reserva_id');
  end if;
  if jsonb_typeof(p->'presente') is distinct from 'boolean' then
    return jsonb_build_object('http', 400, 'error', 'falta_presente');
  end if;

  -- La hora en que se marcó, si Kumaly la manda. Si no, la de llegada.
  if p ? 'marcado_at' and jsonb_typeof(p->'marcado_at') <> 'null' then
    v_marcado := public._kumaly_parse_iso(p->>'marcado_at');
    if v_marcado is null then
      return jsonb_build_object('http', 400, 'error', 'marcado_at_invalido',
        'detalle', 'ISO 8601 con el huso escrito');
    end if;
    v_marcado := least(v_marcado, p_recibido);  -- nada en el futuro
  else
    v_marcado := p_recibido;
  end if;

  select * into v_r from public.reservas where id = public._kumaly_entero(p->'reserva_id') for update;
  if found then
    select * into v_clase from public.clases where id = v_r.clase_id;
  end if;
  -- Una reserva de un estudio no integrado contesta igual que una que no
  -- existe: con la clave de Kumaly no se averigua nada de otros estudios.
  if v_r.id is null or v_clase.id is null or not public._kumaly_activo(v_clase.estudio_id) then
    return jsonb_build_object('http', 404, 'error', 'reserva_no_encontrada');
  end if;

  if v_r.estado not in ('confirmada', 'presente', 'ausente', 'completada') then
    return jsonb_build_object('http', 409, 'error', 'estado_invalido', 'estado', v_r.estado);
  end if;

  -- Ventana: desde donde la deja el panel (reservas_no_marcar_antes_de_tiempo:
  -- cuando la alumna ya no puede cancelar, con 10 min de tolerancia) hasta
  -- 24 h después de que termina la clase.
  select * into v_estudio from public.estudios where id = v_clase.estudio_id;
  v_desde := v_clase.fecha - make_interval(mins => greatest(coalesce(
               v_clase.cancelacion_cierre_minutos, v_estudio.cancelacion_cierre_minutos, 720), 10));
  v_hasta := v_clase.fecha + make_interval(mins => coalesce(v_clase.duracion_min, 0)::int)
             + interval '24 hours';
  if v_ahora < v_desde then
    return jsonb_build_object('http', 422, 'error', 'todavia_no',
      'desde', public._kumaly_iso(v_desde));
  end if;
  if v_ahora > v_hasta then
    return jsonb_build_object('http', 422, 'error', 'fuera_de_plazo',
      'hasta', public._kumaly_iso(v_hasta));
  end if;

  -- Gana el último: el último marcado (panel o Kumaly) queda en el log.
  -- No cuenta el paso a 'completada' del cron, que no es un marcado.
  select max(l.created_at) into v_ultimo
    from public.reservas_estado_log l
   where l.reserva_id = v_r.id
     and l.accion = 'estado'
     and l.estado_nuevo in ('presente', 'ausente', 'confirmada');
  if v_ultimo is not null and v_marcado < v_ultimo then
    return jsonb_build_object('http', 200, 'ok', true, 'aplicado', false,
      'motivo', 'hay_un_marcado_posterior', 'estado', v_r.estado);
  end if;

  v_nuevo := case when (p->>'presente')::boolean then 'presente' else 'ausente' end;
  if v_r.estado = v_nuevo then
    return jsonb_build_object('http', 200, 'ok', true, 'aplicado', false,
      'motivo', 'sin_cambios', 'estado', v_nuevo);
  end if;

  perform set_config('aura.origen', 'kumaly', true);
  -- checked_in_at igual que el panel: hora del marcado en presente, null en ausente.
  update public.reservas
     set estado = v_nuevo,
         checked_in_at = case when v_nuevo = 'presente' then v_marcado else null end
   where id = v_r.id;
  perform set_config('aura.origen', '', true);

  return jsonb_build_object('http', 200, 'ok', true, 'aplicado', true,
    'estado_anterior', v_r.estado, 'estado', v_nuevo);
end;
$function$;

CREATE OR REPLACE FUNCTION public.kumaly_registrar_respuesta(p_id bigint, p_status integer, p_cuerpo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_e public.kumaly_envios%rowtype;
begin
  select * into v_e from public.kumaly_envios where id = p_id for update;
  if not found or v_e.estado <> 'pendiente' then
    return jsonb_build_object('ok', false, 'error', 'no_pendiente');
  end if;

  if p_status between 200 and 299 then
    update public.kumaly_envios
       set estado = 'confirmado', ultimo_status = p_status, ultimo_error = null,
           resuelto_at = now()
     where id = p_id;
    return jsonb_build_object('ok', true, 'estado', 'confirmado');
  end if;

  -- 409 sin_lugar a una reserva: se cae acá mismo, sin esperar al límite.
  -- Un 409 que no dice sin_lugar se trata como error y se reintenta.
  if p_status = 409 and v_e.evento = 'reserva'
     and coalesce(p_cuerpo, '') ilike '%sin_lugar%' then
    perform public._kumaly_cancelar_reserva(v_e.reserva_id, 'sin_lugar');
    update public.kumaly_envios
       set estado = 'rechazado', ultimo_status = p_status,
           ultimo_error = left(p_cuerpo, 500), resuelto_at = now()
     where id = p_id;
    return jsonb_build_object('ok', true, 'estado', 'rechazado');
  end if;

  -- 404 a una CANCELACIÓN: Kumaly no tiene esa reserva, no hay nada que
  -- cancelarle. Insistir no cambia nada (19/11/2026).
  if p_status = 404 and v_e.evento = 'cancelacion' then
    update public.kumaly_envios
       set estado = 'rechazado', ultimo_status = p_status,
           ultimo_error = left(coalesce(p_cuerpo, ''), 500), resuelto_at = now()
     where id = p_id;
    return jsonb_build_object('ok', true, 'estado', 'rechazado');
  end if;

  -- Todo lo demás (404 clase/estudio, 400, 401, 5xx, sin respuesta) se
  -- reintenta cada 10 min hasta el límite: si alguien corrige el dato o la
  -- configuración a tiempo, la reserva entra; si no, al límite se cancela y
  -- se devuelve. Queda anotado para verlo en kumaly_envios.
  update public.kumaly_envios
     set ultimo_status = p_status, ultimo_error = left(coalesce(p_cuerpo, ''), 500)
   where id = p_id;
  return jsonb_build_object('ok', true, 'estado', 'pendiente');
end;
$function$;
