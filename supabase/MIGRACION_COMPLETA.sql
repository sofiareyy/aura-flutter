begin;

alter table public.estudios
  add column if not exists
    reserva_cierre_minutos
    integer
    not null
    default 0;

alter table public.estudios
  add column if not exists
    cancelacion_cierre_minutos
    integer
    not null
    default 720;

alter table public.clases
  add column if not exists
    cancelacion_cierre_minutos
    integer;

alter table public.horarios_fijos
  add column if not exists
    cancelacion_cierre_minutos
    integer;

alter table public.estudios
  drop constraint if exists
    estudios_cierres_rango_check;

alter table public.estudios
  add constraint
    estudios_cierres_rango_check
  check (
    reserva_cierre_minutos
      between 0 and 10080
    and cancelacion_cierre_minutos
      between 0 and 10080
  );

alter table public.clases
  alter column reserva_cierre_minutos
  drop not null;

alter table public.horarios_fijos
  alter column reserva_cierre_minutos
  drop not null;

update public.clases c
   set reserva_cierre_minutos = null
  from public.horarios_fijos h
 where c.horario_fijo_id = h.id
   and c.reserva_cierre_minutos = 0
   and h.reserva_cierre_minutos is null;

update public.clases
   set reserva_cierre_minutos = null
 where reserva_cierre_minutos = 0
   and horario_fijo_id is null;

create or replace function
  public.generar_clases_estudio(
    p_estudio_id int,
    p_weeks int default 4
  )
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamp :=
    (now() at time zone
      'America/Argentina/Buenos_Aires');
  v_week_start date;
  v_week_offset int;
  v_h record;
  v_creadas int := 0;
  v_omitidas int := 0;
  v_fecha timestamp;
  v_estudio_cat text;
  v_hora int;
  v_minuto int;
  v_hora_text text;
  v_existente_id int;
  v_resultado json;
  v_creditos int;
  v_tipo text;
begin
  v_week_start := v_now::date
    - ((extract(isodow from v_now)::int) - 1);

  select categoria
    into v_estudio_cat
    from public.estudios
   where id = p_estudio_id;

  for v_h in
    select *
      from public.horarios_fijos
     where estudio_id = p_estudio_id
       and coalesce(activo, true) = true
  loop
    if v_h.dia_semana is null
       or v_h.dia_semana < 1
       or v_h.dia_semana > 7 then
      v_omitidas := v_omitidas + 1;
      continue;
    end if;

    if v_h.nombre is null
       or trim(v_h.nombre) = '' then
      v_omitidas := v_omitidas + 1;
      continue;
    end if;

    v_hora := coalesce(
      extract(hour from v_h.hora_inicio)::int,
      8
    );
    v_minuto := coalesce(
      extract(minute from v_h.hora_inicio)::int,
      0
    );
    v_hora_text :=
      lpad(v_hora::text, 2, '0')
      || ':'
      || lpad(v_minuto::text, 2, '0');

    v_resultado := public.calcular_precio_clase(
      p_estudio_id,
      coalesce(v_h.categoria, v_estudio_cat),
      v_h.dia_semana,
      v_hora_text
    );
    v_creditos :=
      (v_resultado->>'creditos')::int;
    v_tipo := v_resultado->>'tipo';

    for v_week_offset in 0..(p_weeks - 1) loop
      v_fecha := (
        v_week_start
        + (v_week_offset * 7
           + (v_h.dia_semana - 1))
      )::timestamp
      + make_interval(
          hours => v_hora,
          mins => v_minuto
        );

      select id
        into v_existente_id
        from public.clases
       where estudio_id = p_estudio_id
         and horario_fijo_id = v_h.id
         and fecha between
               v_fecha - interval '1 hour'
           and v_fecha + interval '1 hour'
       limit 1;

      if v_existente_id is not null then
        v_omitidas := v_omitidas + 1;
        continue;
      end if;

      insert into public.clases (
        estudio_id,
        horario_fijo_id,
        nombre,
        instructor,
        instructor_descripcion,
        incluye,
        imagen_url,
        imagen_ajuste,
        galeria_urls,
        fecha,
        duracion_min,
        lugares_total,
        lugares_disponibles,
        creditos,
        reserva_cierre_minutos,
        cancelacion_cierre_minutos,
        categoria,
        sala,
        tipo_precio
      ) values (
        p_estudio_id,
        v_h.id,
        v_h.nombre,
        v_h.instructor,
        v_h.instructor_descripcion,
        v_h.incluye,
        v_h.imagen_url,
        v_h.imagen_ajuste,
        v_h.galeria_urls,
        v_fecha,
        coalesce(v_h.duracion_min, 60),
        coalesce(v_h.lugares_total, 12),
        coalesce(v_h.lugares_total, 12),
        v_creditos,
        v_h.reserva_cierre_minutos,
        v_h.cancelacion_cierre_minutos,
        v_h.categoria,
        v_h.sala,
        v_tipo
      );
      v_creadas := v_creadas + 1;
    end loop;
  end loop;

  return json_build_object(
    'creadas', v_creadas,
    'omitidas', v_omitidas
  );
end;
$$;

grant execute on function
  public.generar_clases_estudio(int, int)
  to authenticated;

create or replace function
  public.set_estudio_cierres(
    p_estudio_id int,
    p_reserva_cierre_minutos int,
    p_cancelacion_cierre_minutos int
  )
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_ok boolean;
begin
  if v_uid is null then
    return json_build_object(
      'ok', false,
      'error', 'No autenticado'
    );
  end if;

  select exists (
    select 1
      from public.estudio_admins
     where estudio_id = p_estudio_id
       and usuario_id = v_uid
  ) into v_ok;

  if not v_ok then
    return json_build_object(
      'ok', false,
      'error', 'Sin permisos'
    );
  end if;

  if p_reserva_cierre_minutos is null
     or p_cancelacion_cierre_minutos is null
     or p_reserva_cierre_minutos
          not between 0 and 10080
     or p_cancelacion_cierre_minutos
          not between 0 and 10080 then
    return json_build_object(
      'ok', false,
      'error', 'Fuera de rango'
    );
  end if;

  update public.estudios
     set reserva_cierre_minutos =
           p_reserva_cierre_minutos,
         cancelacion_cierre_minutos =
           p_cancelacion_cierre_minutos
   where id = p_estudio_id;

  return json_build_object(
    'ok', true,
    'reserva_cierre_minutos',
      p_reserva_cierre_minutos,
    'cancelacion_cierre_minutos',
      p_cancelacion_cierre_minutos
  );
end;
$$;

grant execute on function
  public.set_estudio_cierres(int, int, int)
  to authenticated;

alter table public.estudios
  add column if not exists
    categorias
    text[]
    not null
    default '{}';

update public.estudios
   set categorias = array[trim(categoria)]
 where categorias = '{}'
   and categoria is not null
   and trim(categoria) <> '';

create or replace function
  public.sync_categoria_estudio()
returns trigger
language plpgsql
as $$
begin
  if (new.categorias is null
      or new.categorias = '{}')
     and new.categoria is not null
     and trim(new.categoria) <> '' then
    new.categorias :=
      array[trim(new.categoria)];
  end if;

  new.categoria := case
    when new.categorias is null
      or array_length(new.categorias, 1)
         is null
    then null
    else new.categorias[1]
  end;

  return new;
end;
$$;

drop trigger if exists
  trg_sync_categoria_estudio
  on public.estudios;

create trigger trg_sync_categoria_estudio
  before insert or update
  on public.estudios
  for each row
  execute function
    public.sync_categoria_estudio();

create index if not exists
  estudios_categorias_gin
  on public.estudios
  using gin (categorias);

insert into public.study_categories (nombre)
select v.nombre
  from (values
    ('Pilates'),
    ('Yoga'),
    ('Barre'),
    ('Gym / Funcional'),
    ('Ceramica'),
    ('Tufting'),
    ('Danza'),
    ('Holistico / Bienestar'),
    ('Meditacion'),
    ('Otro')
  ) as v(nombre)
 where not exists (
   select 1
     from public.study_categories sc
    where lower(trim(sc.nombre))
        = lower(trim(v.nombre))
 );

create or replace function
  public.admin_upsert_estudio(
    p_estudio_id bigint default null,
    p_nombre text default null,
    p_categoria text default null,
    p_barrio text default null,
    p_direccion text default null,
    p_descripcion text default null,
    p_foto_url text default null,
    p_instagram text default null,
    p_whatsapp text default null,
    p_web text default null,
    p_lat double precision default null,
    p_lng double precision default null,
    p_activo boolean default true,
    p_comision numeric default null,
    p_fecha_inicio_cobro date default null,
    p_comision_workshop int default null,
    p_cbu text default null,
    p_tipo_precio text default null,
    p_creditos_min integer default null,
    p_creditos_max integer default null,
    p_categorias text[] default null
  )
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_categorias text[];
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  v_categorias := coalesce(
    nullif(
      array(
        select distinct trim(c)
          from unnest(
            coalesce(p_categorias, '{}')
          ) as c
         where trim(coalesce(c, '')) <> ''
      ),
      '{}'
    ),
    case
      when trim(coalesce(p_categoria, ''))
           <> ''
      then array[trim(p_categoria)]
      else '{}'
    end
  );

  if p_estudio_id is null then
    insert into public.estudios (
      nombre,
      categorias,
      barrio,
      direccion,
      descripcion,
      foto_url,
      instagram,
      whatsapp,
      web,
      lat,
      lng,
      activo,
      comision_aura,
      fecha_inicio_cobro,
      comision_workshop,
      cbu,
      tipo_precio,
      creditos_min,
      creditos_max
    ) values (
      p_nombre,
      v_categorias,
      p_barrio,
      p_direccion,
      p_descripcion,
      p_foto_url,
      p_instagram,
      p_whatsapp,
      p_web,
      p_lat,
      p_lng,
      coalesce(p_activo, true),
      coalesce(p_comision, 30),
      p_fecha_inicio_cobro,
      coalesce(p_comision_workshop, 15),
      nullif(trim(coalesce(p_cbu, '')), ''),
      coalesce(
        nullif(
          trim(coalesce(p_tipo_precio, '')),
          ''
        ),
        'rango'
      ),
      p_creditos_min,
      p_creditos_max
    );

    perform public.log_admin_action(
      'Crear estudio',
      coalesce(p_nombre, 'Sin nombre'),
      'estudios'
    );
  else
    update public.estudios
       set nombre = coalesce(
             nullif(trim(p_nombre), ''),
             nombre
           ),
           categorias = case
             when v_categorias = '{}'
             then categorias
             else v_categorias
           end,
           barrio = p_barrio,
           direccion = p_direccion,
           descripcion = p_descripcion,
           foto_url = p_foto_url,
           instagram = p_instagram,
           whatsapp = p_whatsapp,
           web = p_web,
           lat = p_lat,
           lng = p_lng,
           activo = coalesce(p_activo, true),
           comision_aura = coalesce(
             p_comision,
             comision_aura
           ),
           fecha_inicio_cobro =
             p_fecha_inicio_cobro,
           comision_workshop = coalesce(
             p_comision_workshop,
             comision_workshop
           ),
           cbu = nullif(
             trim(coalesce(p_cbu, '')),
             ''
           ),
           tipo_precio = coalesce(
             nullif(
               trim(
                 coalesce(p_tipo_precio, '')
               ),
               ''
             ),
             tipo_precio
           ),
           creditos_min = coalesce(
             p_creditos_min,
             creditos_min
           ),
           creditos_max = coalesce(
             p_creditos_max,
             creditos_max
           )
     where id = p_estudio_id;

    perform public.log_admin_action(
      'Editar estudio',
      coalesce(p_nombre, 'Estudio')
        || ' (#'
        || p_estudio_id
        || ')',
      'estudios'
    );
  end if;
end;
$function$;

drop function if exists
  public.admin_list_studios(text);

create or replace function
  public.admin_list_studios(
    p_search text default null
  )
returns table(
  id bigint,
  nombre text,
  categoria text,
  categorias text[],
  barrio text,
  direccion text,
  descripcion text,
  foto_url text,
  instagram text,
  whatsapp text,
  web text,
  lat double precision,
  lng double precision,
  activo boolean,
  comision_aura numeric,
  fecha_inicio_cobro date,
  comision_workshop integer,
  cbu text,
  tipo_precio text,
  creditos_min integer,
  creditos_max integer,
  admin_email text,
  admin_count bigint,
  admin_emails text
)
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  return query
  select
    e.id,
    e.nombre,
    e.categoria,
    e.categorias,
    e.barrio,
    e.direccion,
    e.descripcion,
    e.foto_url,
    e.instagram,
    e.whatsapp,
    e.web,
    e.lat,
    e.lng,
    coalesce(e.activo, true) as activo,
    coalesce(e.comision_aura, 30)
      as comision_aura,
    e.fecha_inicio_cobro,
    coalesce(e.comision_workshop, 15)
      as comision_workshop,
    e.cbu,
    coalesce(e.tipo_precio, 'rango')
      as tipo_precio,
    e.creditos_min,
    e.creditos_max,
    (select u.email
       from public.usuarios u
      where u.estudio_id = e.id
        and u.rol in (
          'estudio',
          'admin_estudio'
        )
      order by u.email
      limit 1) as admin_email,
    (select count(*)::bigint
       from public.usuarios u
      where u.estudio_id = e.id
        and u.rol in (
          'estudio',
          'admin_estudio'
        )) as admin_count,
    (select string_agg(
              u.email,
              ', ' order by u.email
            )
       from public.usuarios u
      where u.estudio_id = e.id
        and u.rol in (
          'estudio',
          'admin_estudio'
        )) as admin_emails
  from public.estudios e
  where p_search is null
     or e.nombre
          ilike '%' || p_search || '%'
     or coalesce(e.barrio, '')
          ilike '%' || p_search || '%'
     or exists (
       select 1
         from unnest(e.categorias) as c
        where c
          ilike '%' || p_search || '%'
     )
  order by e.nombre;
end;
$function$;

drop policy if exists
  estudio_admin_actualiza_su_estudio
  on public.estudios;

create policy
  estudio_admin_actualiza_su_estudio
  on public.estudios for update
  to authenticated
  using (
    exists (
      select 1
        from public.estudio_admins ea
       where ea.estudio_id = estudios.id
         and ea.usuario_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
        from public.estudio_admins ea
       where ea.estudio_id = estudios.id
         and ea.usuario_id = auth.uid()
    )
  );

commit;
