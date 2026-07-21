-- ============================================================================
-- D4 — Limpieza de overloads y contador de destinatarios de avisos
-- ============================================================================

-- ── Punto 18: admin_upsert_estudio quedó con varias firmas conviviendo ─────
-- (11, 15, 17, 20 y 21 parámetros). PostgREST resuelve por nombre de
-- parámetro, así que una llamada podía caer en una versión vieja que no
-- guarda categorias/cbu/comision_workshop. Se dejan SOLO la de 21 params (la
-- que usa el código) y se dropean las demás, sin importar su firma exacta.
do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig, p.pronargs
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = 'admin_upsert_estudio'
       and p.pronargs <> 21
  loop
    execute 'drop function if exists ' || r.sig::text;
  end loop;
end $$;


-- ── Punto 22: el aviso llegaba solo a reservas 'confirmada' ────────────────
-- Si la profe ya marcó asistencia ('presente'), esos alumnos no recibían el
-- aviso. Se agrega 'presente' a los destinatarios reales (no 'ausente' ni
-- 'completada': no tiene sentido avisar a quien no vino o a una clase pasada).
create or replace function public.enviar_aviso_estudio(
  p_clase_ids bigint[],
  p_mensaje   text,
  p_tipo      text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid        uuid := auth.uid();
  v_estudio_id int;
  v_mensaje    text := trim(coalesce(p_mensaje, ''));
  v_tipo       text := coalesce(nullif(trim(p_tipo), ''), 'aviso_general');
  v_urgente    boolean;
  v_cupo       json;
  v_aviso_id   bigint;
  v_titulo     text;
  v_estudio_nombre text;
  v_destinatarios int := 0;
  v_push_max   int := 3;
  v_hoy        date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  if v_uid is null then
    return json_build_object('ok', false, 'error', 'No autenticado');
  end if;

  if v_mensaje = '' then
    return json_build_object('ok', false, 'error', 'El mensaje no puede estar vacio');
  end if;

  if v_tipo not in ('aviso_general', 'urgente') then
    return json_build_object('ok', false, 'error', 'Tipo invalido');
  end if;

  v_urgente := (v_tipo = 'urgente');

  if p_clase_ids is null or array_length(p_clase_ids, 1) is null then
    return json_build_object('ok', false, 'error', 'Elegi al menos una clase');
  end if;

  if array_length(p_clase_ids, 1) > 10 then
    return json_build_object('ok', false, 'error', 'Maximo 10 clases por envio');
  end if;

  select distinct c.estudio_id
    into v_estudio_id
    from public.clases c
   where c.id = any(p_clase_ids);

  if v_estudio_id is null then
    return json_build_object('ok', false, 'error', 'Clases no encontradas');
  end if;

  if (select count(distinct c.estudio_id)
        from public.clases c
       where c.id = any(p_clase_ids)) > 1 then
    return json_build_object(
      'ok', false,
      'error', 'Las clases tienen que ser del mismo estudio'
    );
  end if;

  if not exists (
    select 1 from public.estudio_admins ea
     where ea.estudio_id = v_estudio_id
       and ea.usuario_id = v_uid
       and ea.rol in ('estudio', 'admin_estudio')
  ) then
    return json_build_object('ok', false, 'error', 'Sin permisos');
  end if;

  if not v_urgente then
    v_cupo := public.avisos_generales_restantes(v_estudio_id);
    if (v_cupo->>'restantes')::int <= 0 then
      return json_build_object('ok', false, 'error', 'limite_mensual', 'cupo', v_cupo);
    end if;
  end if;

  select nombre into v_estudio_nombre from public.estudios where id = v_estudio_id;

  v_titulo := case
    when v_urgente then '🚨 ' || coalesce(v_estudio_nombre, 'Tu estudio') || ' — Aviso urgente'
    else '📢 ' || coalesce(v_estudio_nombre, 'Tu estudio')
  end;

  insert into public.avisos_envios (estudio_id, enviado_por, tipo, mensaje, clase_ids)
  values (v_estudio_id, v_uid, v_tipo, v_mensaje, p_clase_ids)
  returning id into v_aviso_id;

  with destinatarios as (
    select distinct r.usuario_id
      from public.reservas r
     where r.clase_id = any(p_clase_ids)
       -- 'presente' incluido (punto 22): a quien ya se le marcó asistencia
       -- igual le llega el aviso.
       and r.estado in ('confirmada', 'presente')
       and r.usuario_id is not null
  ),
  uso_hoy as (
    select ae.usuario_id, count(*) as enviadas
      from public.avisos_entregas ae
      join public.avisos_envios av on av.id = ae.aviso_id
     where ae.canal in ('push', 'email')
       and av.tipo <> 'urgente'
       and (ae.created_at at time zone 'America/Argentina/Buenos_Aires')::date = v_hoy
     group by ae.usuario_id
  ),
  ins_notif as (
    insert into public.notificaciones_usuario (usuario_id, titulo, mensaje, tipo, leida)
    select d.usuario_id, v_titulo, v_mensaje, 'aviso_estudio', false
      from destinatarios d
    returning usuario_id
  ),
  ins_in_app as (
    insert into public.avisos_entregas (aviso_id, usuario_id, canal)
    select v_aviso_id, d.usuario_id, 'in_app' from destinatarios d
    on conflict do nothing
    returning usuario_id
  ),
  ins_externo as (
    insert into public.avisos_entregas (aviso_id, usuario_id, canal)
    select v_aviso_id, d.usuario_id,
           case when v_urgente then 'email' else 'push' end
      from destinatarios d
      left join uso_hoy u on u.usuario_id = d.usuario_id
     where v_urgente or coalesce(u.enviadas, 0) < v_push_max
    on conflict do nothing
    returning usuario_id
  )
  select count(*) into v_destinatarios from ins_notif;

  update public.avisos_envios set destinatarios = v_destinatarios where id = v_aviso_id;

  insert into public.notificaciones_usuario (usuario_id, titulo, mensaje, tipo, leida)
  select ea.usuario_id, '✅ Aviso enviado',
         'Se envio a ' || v_destinatarios || ' alumna'
           || case when v_destinatarios = 1 then '' else 's' end
           || ': "' || v_mensaje || '"',
         'aviso_confirmacion', false
    from public.estudio_admins ea
   where ea.estudio_id = v_estudio_id
     and ea.usuario_id <> v_uid;

  return json_build_object(
    'ok', true,
    'aviso_id', v_aviso_id,
    'destinatarios', v_destinatarios,
    'tipo', v_tipo,
    'cupo', case when v_urgente then null
                 else public.avisos_generales_restantes(v_estudio_id) end
  );
end;
$$;

grant execute on function public.enviar_aviso_estudio(bigint[], text, text)
  to authenticated;
