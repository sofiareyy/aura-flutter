-- AURA - Comisión de workshops por estudio + CBU editable desde backoffice
-- (2026-07-09).
--
-- FIX 3: hasta ahora la comisión de workshops (15%) era una constante hardcodeada
-- en admin_liquidaciones_screen.dart. Ahora es una columna por estudio,
-- editable SOLO desde el backoffice (el estudio no la ve ni la edita).
--   * clase normal  -> estudios.comision_aura     (default 30)
--   * workshop       -> estudios.comision_workshop (default 15)
--
-- FIX 6: el formulario de estudio del backoffice ahora también edita el CBU
-- (la columna estudios.cbu ya existe; se usa en el panel del estudio).

-- 1. Columna nueva ---------------------------------------------------------
alter table public.estudios add column if not exists comision_workshop integer not null default 15;

comment on column public.estudios.comision_workshop is 'Comision de Aura (%) para clases tipo workshop. Default 15. Editable solo desde el backoffice, no por el estudio.';

-- 2. admin_upsert_estudio: aceptar comisión workshop + cbu -----------------
drop function if exists public.admin_upsert_estudio(
  bigint, text, text, text, text, text, text, text, text, text,
  double precision, double precision, boolean, numeric, date);

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
  p_lat double precision default null,
  p_lng double precision default null,
  p_activo boolean default true,
  p_comision numeric default null,
  p_fecha_inicio_cobro date default null,
  p_comision_workshop integer default null,
  p_cbu text default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  if p_estudio_id is null then
    insert into public.estudios (
      nombre, categoria, barrio, direccion, descripcion,
      foto_url, instagram, whatsapp, web, lat, lng, activo,
      comision_aura, fecha_inicio_cobro, comision_workshop, cbu
    ) values (
      p_nombre, p_categoria, p_barrio, p_direccion, p_descripcion,
      p_foto_url, p_instagram, p_whatsapp, p_web, p_lat, p_lng,
      coalesce(p_activo, true),
      coalesce(p_comision, 30), p_fecha_inicio_cobro,
      coalesce(p_comision_workshop, 15),
      nullif(trim(coalesce(p_cbu, '')), '')
    );

    perform public.log_admin_action(
      'Crear estudio',
      coalesce(p_nombre, 'Sin nombre'),
      'estudios'
    );
  else
    update public.estudios
       set nombre = coalesce(nullif(trim(p_nombre), ''), nombre),
           categoria = nullif(trim(coalesce(p_categoria, '')), ''),
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
           comision_aura = coalesce(p_comision, comision_aura),
           fecha_inicio_cobro = p_fecha_inicio_cobro,
           comision_workshop = coalesce(p_comision_workshop, comision_workshop),
           cbu = nullif(trim(coalesce(p_cbu, '')), '')
     where id = p_estudio_id;

    perform public.log_admin_action(
      'Editar estudio',
      coalesce(p_nombre, 'Estudio') || ' (#' || p_estudio_id || ')',
      'estudios'
    );
  end if;
end;
$function$;

-- 3. admin_list_studios: devolver comisión workshop + cbu ------------------
drop function if exists public.admin_list_studios(text);

create or replace function public.admin_list_studios(p_search text default null)
returns table(
  id bigint, nombre text, categoria text, barrio text, direccion text,
  descripcion text, foto_url text, instagram text, whatsapp text, web text,
  lat double precision, lng double precision, activo boolean,
  comision_aura numeric, fecha_inicio_cobro date,
  comision_workshop integer, cbu text,
  admin_email text, admin_count bigint, admin_emails text
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
    coalesce(e.comision_aura, 30) as comision_aura,
    e.fecha_inicio_cobro,
    coalesce(e.comision_workshop, 15) as comision_workshop,
    e.cbu,
    (
      select u.email
      from public.usuarios u
      where u.estudio_id = e.id
        and u.rol in ('estudio', 'admin_estudio')
      order by u.email
      limit 1
    ) as admin_email,
    (
      select count(*)::bigint
      from public.usuarios u
      where u.estudio_id = e.id
        and u.rol in ('estudio', 'admin_estudio')
    ) as admin_count,
    (
      select string_agg(u.email, ', ' order by u.email)
      from public.usuarios u
      where u.estudio_id = e.id
        and u.rol in ('estudio', 'admin_estudio')
    ) as admin_emails
  from public.estudios e
  where p_search is null
     or e.nombre ilike '%' || p_search || '%'
     or coalesce(e.barrio, '') ilike '%' || p_search || '%'
     or coalesce(e.categoria, '') ilike '%' || p_search || '%'
  order by e.nombre;
end;
$function$;
