-- Kumaly (18/11/2026, segunda parte): los mensajes que les mandamos llevan
-- "estudio_id" (el número, ej. 70) y "estudio" pasa a ser el NOMBRE del
-- estudio. Lo pidió Kumaly. Sólo cambia kumaly_encolar; el resto de
-- 20261118170000_kumaly.sql queda igual.
--
-- Los envíos ya anotados guardan su payload: al aplicar esto no había
-- ninguno (la integración estaba apagada).

create or replace function public.kumaly_encolar()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_clase   public.clases%rowtype;
  v_nombre  text;
  v_mail    text;
  v_base    jsonb;
  v_res     public.kumaly_envios%rowtype;
  v_motivo  text;
  v_limite  timestamptz;
  v_estudio text;
begin
  -- Lo que vino de Kumaly (o lo que cancelamos porque Kumaly no lo tomó) no
  -- vuelve a Kumaly.
  if coalesce(current_setting('aura.origen', true), '') = 'kumaly' then
    return new;
  end if;

  select * into v_clase from public.clases where id = new.clase_id;
  if not found or not public._kumaly_activo(v_clase.estudio_id) then
    return new;
  end if;

  select e.nombre into v_estudio from public.estudios e where e.id = v_clase.estudio_id;

  select coalesce(nullif(btrim(u.nombre), ''), ''), coalesce(au.email, u.email)
    into v_nombre, v_mail
    from (select 1) x
    left join public.usuarios u on u.id = new.usuario_id
    left join auth.users au on au.id = new.usuario_id;

  v_base := jsonb_build_object(
    'reserva_id',   new.id,
    'estudio_id',   v_clase.estudio_id,
    'estudio',      v_estudio,
    'clase',        v_clase.nombre,
    'sala',         v_clase.sala,
    'inicio',       public._kumaly_iso(v_clase.fecha),
    'duracion_min', v_clase.duracion_min,
    'alumna',       v_nombre,
    'mail',         v_mail);

  -- RESERVA: nace confirmada, o sale de la lista de espera.
  if new.estado = 'confirmada'
     and (tg_op = 'INSERT' or old.estado = 'pre_confirmada') then
    v_limite := least(v_clase.fecha at time zone 'America/Argentina/Buenos_Aires',
                      now() + interval '24 hours');
    insert into public.kumaly_envios (reserva_id, evento, payload, limite)
    values (new.id, 'reserva',
            v_base || jsonb_build_object('evento', 'reserva', 'motivo', null),
            v_limite)
    on conflict (reserva_id, evento) do nothing;
    return new;
  end if;

  -- CANCELACIÓN de algo que estaba tomado.
  if tg_op = 'UPDATE'
     and old.estado in ('confirmada', 'presente')
     and new.estado in ('cancelada', 'cancelada_por_estudio') then

    select * into v_res from public.kumaly_envios
     where reserva_id = new.id and evento = 'reserva' for update;
    if not found then
      return new;  -- reserva de antes de prender la integración
    end if;

    -- Nunca salió: se descarta la reserva y no hace falta cancelar nada.
    if v_res.estado = 'pendiente' and v_res.intentos = 0 then
      update public.kumaly_envios
         set estado = 'descartado', resuelto_at = now(),
             ultimo_error = 'la reserva se canceló antes de mandarse'
       where id = v_res.id;
      return new;
    end if;
    -- Kumaly no la tomó: no hay nada que cancelarle.
    if v_res.estado in ('rechazado', 'vencido', 'descartado') then
      return new;
    end if;

    v_motivo := case when new.estado = 'cancelada' then 'alumna' else 'estudio' end;
    insert into public.kumaly_envios (reserva_id, evento, payload, limite)
    values (new.id, 'cancelacion',
            v_base || jsonb_build_object('evento', 'cancelacion', 'motivo', v_motivo),
            now() + interval '24 hours')
    on conflict (reserva_id, evento) do nothing;
  end if;

  return new;
end;
$function$;

