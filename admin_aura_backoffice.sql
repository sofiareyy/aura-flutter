create table if not exists public.admin_users (
  user_id uuid primary key references public.usuarios(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.admin_users enable row level security;

drop policy if exists "admin_users_self_read" on public.admin_users;
create policy "admin_users_self_read"
  on public.admin_users
  for select
  using (auth.uid() = user_id);

create or replace function public.is_admin()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  return exists (
    select 1 from public.admin_users where user_id = auth.uid()
  );
end;
$$;

alter table public.estudios
  add column if not exists activo boolean default true;

create or replace function public.admin_dashboard_metrics()
returns table(
  usuarios_total bigint,
  usuarios_activos bigint,
  estudios_total bigint,
  estudios_activos bigint,
  reservas_total bigint,
  reservas_hoy bigint,
  reservas_mes bigint,
  creditos_consumidos bigint,
  ingresos_estimados bigint,
  ocupacion_promedio integer,
  top_estudio text,
  top_clase text,
  top_categoria text,
  actividad_reciente text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  return query
  with reservas_activas as (
    select r.*, c.nombre as clase_nombre, c.estudio_id, c.creditos as clase_creditos,
           e.nombre as estudio_nombre, e.categoria, coalesce(e.valor_credito, 6000) as valor_credito
    from public.reservas r
    left join public.clases c on c.id = r.clase_id
    left join public.estudios e on e.id = c.estudio_id
    where r.estado <> 'cancelada'
  ),
  resumen as (
    select
      (select count(*) from public.usuarios) as usuarios_total,
      (select count(distinct usuario_id) from public.reservas where created_at >= now() - interval '30 days') as usuarios_activos,
      (select count(*) from public.estudios) as estudios_total,
      (select count(*) from public.estudios where coalesce(activo, true) = true) as estudios_activos,
      (select count(*) from public.reservas) as reservas_total,
      (select count(*) from public.reservas where created_at::date = current_date) as reservas_hoy,
      (select count(*) from public.reservas where date_trunc('month', created_at) = date_trunc('month', now())) as reservas_mes,
      (select coalesce(sum(creditos_usados), 0) from reservas_activas) as creditos_consumidos,
      (select coalesce(sum(creditos_usados * valor_credito), 0) from reservas_activas) as ingresos_estimados
  )
  select
    r.usuarios_total,
    r.usuarios_activos,
    r.estudios_total,
    r.estudios_activos,
    r.reservas_total,
    r.reservas_hoy,
    r.reservas_mes,
    r.creditos_consumidos,
    r.ingresos_estimados,
    coalesce((
      select round(avg(case
        when coalesce(c.lugares_total,0) > 0 then
          ((coalesce(c.lugares_total,0) - coalesce(c.lugares_disponibles, coalesce(c.lugares_total,0)))::numeric / c.lugares_total::numeric) * 100
        else 0 end))
      from public.clases c
      where c.fecha >= now() - interval '30 days'
    )::int, 0) as ocupacion_promedio,
    coalesce((select estudio_nombre from reservas_activas group by estudio_nombre order by count(*) desc limit 1), 'Sin datos') as top_estudio,
    coalesce((select clase_nombre from reservas_activas group by clase_nombre order by count(*) desc limit 1), 'Sin datos') as top_clase,
    coalesce((select categoria from reservas_activas group by categoria order by count(*) desc limit 1), 'Sin datos') as top_categoria,
    coalesce((select 'Última reserva: ' || coalesce(usuario_id::text, '') || ' en ' || coalesce(estudio_nombre, 'estudio') from reservas_activas order by created_at desc limit 1), 'Todavía no hay actividad registrada') as actividad_reciente
  from resumen r;
end;
$$;

create or replace function public.admin_list_users(p_search text default null)
returns table(
  id uuid,
  nombre text,
  email text,
  plan text,
  creditos integer
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  return query
  select u.id, u.nombre, u.email, u.plan, coalesce(u.creditos, 0)::int
  from public.usuarios u
  where p_search is null
     or u.nombre ilike '%' || p_search || '%'
     or u.email ilike '%' || p_search || '%'
  order by u.nombre;
end;
$$;

create or replace function public.admin_adjust_user_credits(p_user_id uuid, p_delta integer)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  update public.usuarios
     set creditos = greatest(coalesce(creditos, 0) + p_delta, 0)
   where id = p_user_id;
end;
$$;

create or replace function public.admin_update_user(
  p_user_id uuid,
  p_nombre text,
  p_plan text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  update public.usuarios
     set nombre = coalesce(nullif(trim(p_nombre), ''), nombre),
         plan = p_plan
   where id = p_user_id;
end;
$$;

create or replace function public.admin_list_studios(p_search text default null)
returns table(
  id bigint,
  nombre text,
  categoria text,
  barrio text,
  direccion text,
  descripcion text,
  activo boolean
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  return query
  select e.id, e.nombre, e.categoria, e.barrio, e.direccion, e.descripcion, coalesce(e.activo, true)
  from public.estudios e
  where p_search is null
     or e.nombre ilike '%' || p_search || '%'
     or coalesce(e.barrio, '') ilike '%' || p_search || '%'
     or coalesce(e.categoria, '') ilike '%' || p_search || '%'
  order by e.nombre;
end;
$$;

create or replace function public.admin_upsert_estudio(
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
  p_activo boolean default true
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  if p_estudio_id is null then
    insert into public.estudios (
      nombre, categoria, barrio, direccion, descripcion,
      foto_url, instagram, whatsapp, web, activo
    ) values (
      p_nombre, p_categoria, p_barrio, p_direccion, p_descripcion,
      p_foto_url, p_instagram, p_whatsapp, p_web, coalesce(p_activo, true)
    );
  else
    update public.estudios
       set nombre = coalesce(nullif(trim(p_nombre), ''), nombre),
           categoria = coalesce(nullif(trim(p_categoria), ''), categoria),
           barrio = p_barrio,
           direccion = p_direccion,
           descripcion = p_descripcion,
           foto_url = p_foto_url,
           instagram = p_instagram,
           whatsapp = p_whatsapp,
           web = p_web,
           activo = coalesce(p_activo, true)
     where id = p_estudio_id;
  end if;
end;
$$;

create or replace function public.admin_list_reservas(p_search text default null)
returns table(
  id bigint,
  estado text,
  creditos_usados integer,
  usuario_nombre text,
  estudio_nombre text,
  clase_nombre text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  return query
  select
    r.id,
    r.estado,
    coalesce(r.creditos_usados, 0)::int,
    coalesce(u.nombre, 'Usuario'),
    coalesce(e.nombre, 'Estudio'),
    coalesce(c.nombre, 'Clase')
  from public.reservas r
  left join public.usuarios u on u.id = r.usuario_id
  left join public.clases c on c.id = r.clase_id
  left join public.estudios e on e.id = c.estudio_id
  where p_search is null
     or coalesce(u.nombre, '') ilike '%' || p_search || '%'
     or coalesce(e.nombre, '') ilike '%' || p_search || '%'
     or coalesce(c.nombre, '') ilike '%' || p_search || '%'
  order by r.created_at desc
  limit 150;
end;
$$;

create or replace function public.admin_cancel_reserva(p_reserva_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  update public.reservas
     set estado = 'cancelada'
   where id = p_reserva_id;
end;
$$;

create or replace function public.admin_pricing_snapshot()
returns table(
  planes_text text,
  packs_text text,
  valor_credito bigint
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  return query
  select
    coalesce((
      select string_agg(nombre || ': ' || creditos || ' cr - $' || precio, E'\n')
      from public.pricing_planes
      where coalesce(activo, true) = true
    ), 'Sin planes configurados'),
    coalesce((
      select string_agg(nombre || ': ' || creditos || ' cr - $' || precio, E'\n')
      from public.pricing_credit_packs
      where coalesce(activo, true) = true
    ), 'Sin packs configurados'),
    coalesce((select max(valor_credito)::bigint from public.estudios), 6000::bigint);
end;
$$;

create or replace function public.admin_update_global_credit_value(p_value bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  update public.estudios
     set valor_credito = p_value;
end;
$$;
