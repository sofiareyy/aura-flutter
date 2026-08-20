-- ============================================================================
-- AURA — Separar datos de cobro de `estudios` (SEGURIDAD)
-- ============================================================================
-- Aplicado a mano vía la Management API el 2026-08-20.
-- Plan completo y checklist: supabase/pendientes/SEPARAR_DATOS_COBRO.md
--
-- MOTIVO: `estudios` era catálogo público Y tabla de datos de cobro a la vez.
-- Con `.select()` = select=*, cualquier usuaria logueada que abría Explorar
-- recibía en el JSON el cbu/alias/banco/titular de los 9 estudios.
--
-- fecha_inicio_cobro NO se movió: sigue en `estudios` (no es CBU ni margen, y
-- moverla rompía el cálculo del período de gracia en builds viejos).
--
-- Los pasos 7 (policy anon) y 8 (DROP de columnas viejas) NO están acá todavía:
-- van cuando cierre el gate de prueba en Chrome.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- PASO 1: tabla nueva + migración + RLS + trigger
-- ---------------------------------------------------------------------------
create table public.estudios_datos_cobro as
select id as estudio_id,
       cbu, alias, banco, titular,
       comision_aura, comision_workshop, valor_credito, dia_pago
  from public.estudios;

alter table public.estudios_datos_cobro
  add primary key (estudio_id),
  add constraint estudios_datos_cobro_estudio_fk
      foreign key (estudio_id) references public.estudios(id) on delete cascade;

-- Defaults espejo de `estudios`, para que un estudio nuevo quede idéntico en
-- ambas tablas mientras dure el dual-write.
alter table public.estudios_datos_cobro
  alter column comision_aura     set default 30,
  alter column comision_workshop set default 15,
  alter column dia_pago          set default 5,
  alter column valor_credito     set default 6000;

alter table public.estudios_datos_cobro enable row level security;
revoke all on public.estudios_datos_cobro from anon;
grant select, insert, update on public.estudios_datos_cobro to authenticated;
grant all on public.estudios_datos_cobro to service_role;

create policy "datos_cobro_select" on public.estudios_datos_cobro
  for select to authenticated
  using (public.is_admin() or public.es_miembro_de_estudio(estudio_id));

create policy "datos_cobro_update" on public.estudios_datos_cobro
  for update to authenticated
  using  (public.is_admin() or public.es_miembro_de_estudio(estudio_id))
  with check (public.is_admin() or public.es_miembro_de_estudio(estudio_id));

create policy "datos_cobro_insert" on public.estudios_datos_cobro
  for insert to authenticated
  with check (public.is_admin() or public.es_miembro_de_estudio(estudio_id));

-- La dueña edita su CBU, pero las comisiones las define Aura. Mismo patrón que
-- estudios_bloquear_columnas_aura: exime a service_role/postgres, o sea a los
-- RPC security definer del backoffice.
create or replace function public.datos_cobro_bloquear_columnas_aura()
returns trigger language plpgsql set search_path to 'public' as $fn$
begin
  if current_user not in ('authenticated','anon') then return new; end if;
  if new.comision_aura     is distinct from old.comision_aura
  or new.comision_workshop is distinct from old.comision_workshop
  or new.valor_credito     is distinct from old.valor_credito
  or new.dia_pago          is distinct from old.dia_pago then
    raise exception 'Comisiones y precios los define Aura desde el backoffice';
  end if;
  return new;
end
$fn$;

drop trigger if exists trg_datos_cobro_columnas_aura on public.estudios_datos_cobro;
create trigger trg_datos_cobro_columnas_aura
  before update on public.estudios_datos_cobro
  for each row execute function public.datos_cobro_bloquear_columnas_aura();

-- PASO 3: funciones de la base con DUAL-WRITE
-- Las lecturas ya apuntan a estudios_datos_cobro; las escrituras van a AMBAS
-- tablas hasta el paso 8 (así el rollback sigue siendo un simple drop table).

-- 0) Defaults espejo, para que un estudio nuevo quede idéntico en ambas tablas.
alter table public.estudios_datos_cobro
  alter column comision_aura     set default 30,
  alter column comision_workshop set default 15,
  alter column dia_pago          set default 5,
  alter column valor_credito     set default 6000;


-- 1) admin_upsert_estudio: MISMA FIRMA. Catálogo -> estudios, cobro -> ambas.
create or replace function public.admin_upsert_estudio(
  p_estudio_id bigint default null, p_nombre text default null,
  p_categoria text default null, p_barrio text default null,
  p_direccion text default null, p_descripcion text default null,
  p_foto_url text default null, p_instagram text default null,
  p_whatsapp text default null, p_web text default null,
  p_lat double precision default null, p_lng double precision default null,
  p_activo boolean default true, p_comision numeric default null,
  p_fecha_inicio_cobro date default null, p_comision_workshop integer default null,
  p_cbu text default null, p_tipo_precio text default null,
  p_creditos_min integer default null, p_creditos_max integer default null,
  p_categorias text[] default null)
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_categorias text[];
  v_id bigint;
  v_cbu text := nullif(trim(coalesce(p_cbu, '')), '');
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  v_categorias := coalesce(
    nullif(
      array(select distinct trim(c) from unnest(coalesce(p_categorias, '{}')) as c
             where trim(coalesce(c, '')) <> ''),
      '{}'),
    case when trim(coalesce(p_categoria, '')) <> ''
         then array[trim(p_categoria)] else '{}' end);

  if p_estudio_id is null then
    insert into public.estudios (
      nombre, categorias, barrio, direccion, descripcion, foto_url,
      instagram, whatsapp, web, lat, lng, activo,
      comision_aura, fecha_inicio_cobro, comision_workshop, cbu,
      tipo_precio, creditos_min, creditos_max
    ) values (
      p_nombre, v_categorias, p_barrio, p_direccion, p_descripcion, p_foto_url,
      p_instagram, p_whatsapp, p_web, p_lat, p_lng, coalesce(p_activo, true),
      coalesce(p_comision, 30), p_fecha_inicio_cobro,
      coalesce(p_comision_workshop, 15), v_cbu,
      coalesce(nullif(trim(coalesce(p_tipo_precio, '')), ''), 'rango'),
      p_creditos_min, p_creditos_max
    ) returning id into v_id;

    perform public.log_admin_action('Crear estudio', coalesce(p_nombre, 'Sin nombre'), 'estudios');
  else
    v_id := p_estudio_id;
    update public.estudios
       set nombre = coalesce(nullif(trim(p_nombre), ''), nombre),
           categorias = case when v_categorias = '{}' then categorias else v_categorias end,
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
           cbu = v_cbu,
           tipo_precio = coalesce(nullif(trim(coalesce(p_tipo_precio, '')), ''), tipo_precio),
           creditos_min = coalesce(p_creditos_min, creditos_min),
           creditos_max = coalesce(p_creditos_max, creditos_max)
     where id = p_estudio_id;

    perform public.log_admin_action('Editar estudio',
      coalesce(p_nombre, 'Estudio') || ' (#' || p_estudio_id || ')', 'estudios');
  end if;

  -- Espejo en la tabla de cobro (misma semántica que arriba).
  -- current_user aquí es el owner de la función -> el trigger de bloqueo no aplica.
  insert into public.estudios_datos_cobro (
    estudio_id, cbu, comision_aura, comision_workshop
  ) values (
    v_id, v_cbu, coalesce(p_comision, 30), coalesce(p_comision_workshop, 15)
  )
  on conflict (estudio_id) do update
    set cbu               = excluded.cbu,
        comision_aura     = coalesce(p_comision, public.estudios_datos_cobro.comision_aura),
        comision_workshop = coalesce(p_comision_workshop, public.estudios_datos_cobro.comision_workshop);
end;
$function$;


-- 2) admin_list_studios: MISMO RETURNS TABLE. cbu/comisiones desde la tabla nueva,
--    fecha_inicio_cobro sigue saliendo de estudios.
create or replace function public.admin_list_studios(p_search text default null)
returns table(id bigint, nombre text, categoria text, categorias text[], barrio text,
  direccion text, descripcion text, foto_url text, instagram text, whatsapp text,
  web text, lat double precision, lng double precision, activo boolean,
  comision_aura numeric, fecha_inicio_cobro date, comision_workshop integer,
  cbu text, tipo_precio text, creditos_min integer, creditos_max integer,
  admin_email text, admin_count bigint, admin_emails text)
language plpgsql security definer set search_path to 'public'
as $function$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  return query
  select
    e.id, e.nombre, e.categoria, e.categorias, e.barrio, e.direccion,
    e.descripcion, e.foto_url, e.instagram, e.whatsapp, e.web, e.lat, e.lng,
    coalesce(e.activo, true) as activo,
    coalesce(d.comision_aura, 30) as comision_aura,
    e.fecha_inicio_cobro,
    coalesce(d.comision_workshop, 15) as comision_workshop,
    d.cbu,
    coalesce(e.tipo_precio, 'rango') as tipo_precio,
    e.creditos_min, e.creditos_max,
    (select u.email from public.usuarios u
      where u.estudio_id = e.id and u.rol in ('estudio', 'admin_estudio')
      order by u.email limit 1) as admin_email,
    (select count(*)::bigint from public.usuarios u
      where u.estudio_id = e.id and u.rol in ('estudio', 'admin_estudio')) as admin_count,
    (select string_agg(u.email, ', ' order by u.email) from public.usuarios u
      where u.estudio_id = e.id and u.rol in ('estudio', 'admin_estudio')) as admin_emails
  from public.estudios e
  left join public.estudios_datos_cobro d on d.estudio_id = e.id
  where p_search is null
     or e.nombre ilike '%' || p_search || '%'
     or coalesce(e.barrio, '') ilike '%' || p_search || '%'
     or exists (select 1 from unnest(e.categorias) as c where c ilike '%' || p_search || '%')
  order by e.nombre;
end;
$function$;


-- 3) admin_dashboard_metrics: valor_credito desde la tabla nueva.
create or replace function public.admin_dashboard_metrics(
  p_from timestamp with time zone default null,
  p_to timestamp with time zone default null)
returns table(usuarios_total bigint, usuarios_activos bigint, estudios_total bigint,
  estudios_activos bigint, reservas_total bigint, reservas_hoy bigint,
  reservas_mes bigint, creditos_consumidos bigint, ingresos_estimados bigint,
  ocupacion_promedio integer, top_estudio text, top_clase text, top_categoria text,
  actividad_reciente text)
language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_from timestamptz := coalesce(p_from, date_trunc('month', now()));
  v_to   timestamptz := coalesce(p_to, now());
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  return query
  with reservas_periodo as (
    select r.*, c.nombre as clase_nombre, e.nombre as estudio_nombre, e.categoria,
           coalesce(dc.valor_credito, 6000) as valor_credito
    from public.reservas r
    left join public.clases c on c.id = r.clase_id
    left join public.estudios e on e.id = c.estudio_id
    left join public.estudios_datos_cobro dc on dc.estudio_id = c.estudio_id
    where r.estado <> 'cancelada'
      and r.created_at >= v_from
      and r.created_at < (v_to + interval '1 day')
  ),
  resumen as (
    select
      (select count(*) from public.usuarios) as usuarios_total,
      (select count(distinct rp.usuario_id) from reservas_periodo rp) as usuarios_activos,
      (select count(*) from public.estudios) as estudios_total,
      (select count(*) from public.estudios where coalesce(activo, true) = true) as estudios_activos,
      (select count(*) from public.reservas) as reservas_total,
      (select count(*) from public.reservas where created_at::date = current_date) as reservas_hoy,
      (select count(*) from reservas_periodo) as reservas_mes,
      (select coalesce(sum(rp.creditos_usados), 0)::bigint from reservas_periodo rp) as creditos_consumidos,
      (select coalesce(sum((rp.creditos_usados * rp.valor_credito)::bigint), 0)::bigint from reservas_periodo rp) as ingresos_estimados
  )
  select
    r.usuarios_total, r.usuarios_activos, r.estudios_total, r.estudios_activos,
    r.reservas_total, r.reservas_hoy, r.reservas_mes, r.creditos_consumidos,
    r.ingresos_estimados,
    coalesce((
      select round(avg(case
        when coalesce(c.lugares_total, 0) > 0 then
          ((coalesce(c.lugares_total, 0) - coalesce(c.lugares_disponibles, coalesce(c.lugares_total, 0)))::numeric / c.lugares_total::numeric) * 100
        else 0 end))::int
      from public.clases c
      where c.fecha >= v_from and c.fecha < (v_to + interval '1 day')
    ), 0) as ocupacion_promedio,
    coalesce((select rp.estudio_nombre from reservas_periodo rp group by rp.estudio_nombre order by count(*) desc limit 1), 'Sin datos') as top_estudio,
    coalesce((select rp.clase_nombre from reservas_periodo rp group by rp.clase_nombre order by count(*) desc limit 1), 'Sin datos') as top_clase,
    coalesce((select rp.categoria from reservas_periodo rp group by rp.categoria order by count(*) desc limit 1), 'Sin datos') as top_categoria,
    coalesce((select 'Última reserva del período: ' || coalesce(rp.estudio_nombre, 'estudio') from reservas_periodo rp order by rp.created_at desc limit 1), 'Todavía no hay actividad registrada') as actividad_reciente
  from resumen r;
end;
$function$;


-- 4) admin_pricing_snapshot: promedio de valor_credito desde la tabla nueva.
create or replace function public.admin_pricing_snapshot()
returns table(planes_text text, packs_text text, valor_credito integer)
language plpgsql security definer set search_path to 'public'
as $function$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  return query
  select
    coalesce((select string_agg(pp.nombre || ': ' || pp.creditos || ' cr - $' || pp.precio, E'\n')
      from public.pricing_planes pp where coalesce(pp.activo, true) = true), 'Sin planes configurados'),
    coalesce((select string_agg(pc.nombre || ': ' || pc.creditos || ' cr - $' || pc.precio, E'\n')
      from public.pricing_credit_packs pc where coalesce(pc.activo, true) = true), 'Sin packs configurados'),
    coalesce((select round(avg(d.valor_credito))::int
      from public.estudios_datos_cobro d where d.valor_credito is not null), 6000);
end;
$function$;


-- 5) admin_set_valor_credito_ars: DUAL-WRITE.
create or replace function public.admin_set_valor_credito_ars(p_value bigint)
returns void language plpgsql security definer set search_path to 'public'
as $function$
begin
  if not exists (select 1 from public.admin_users where user_id = auth.uid()) then
    raise exception 'No autorizado';
  end if;
  if p_value is null or p_value <= 0 then
    raise exception 'El valor debe ser mayor a 0';
  end if;

  insert into public.configuracion_global (clave, valor, updated_at)
  values ('valor_credito_ars', p_value::text, now())
  on conflict (clave) do update set valor = excluded.valor, updated_at = now();

  perform public.recalc_pack_prices();

  update public.estudios set valor_credito = p_value;                 -- dual-write
  update public.estudios_datos_cobro set valor_credito = p_value;     -- dual-write
end;
$function$;


-- 6) admin_update_global_credit_value: DUAL-WRITE.
create or replace function public.admin_update_global_credit_value(p_value integer)
returns void language plpgsql security definer set search_path to 'public'
as $function$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  if p_value is null or p_value <= 0 then
    raise exception 'Valor inválido';
  end if;

  update public.estudios set valor_credito = p_value where true;               -- dual-write
  update public.estudios_datos_cobro set valor_credito = p_value where true;   -- dual-write

  update public.pricing_credit_packs set precio = creditos * p_value where true;
  update public.pricing_planes set precio = creditos * p_value, ahorro = null where true;

  perform public.log_admin_action('Actualizar valor crédito', 'Nuevo valor: $' || p_value, 'config');
end;
$function$;


-- admin_list_studios: casts explícitos.
-- El RETURNS TABLE declara id bigint / creditos_* integer, pero estudios.id es
-- integer. Sin cast, RETURN QUERY tira 42804 y la función falla SIEMPRE.
-- Estaba así desde COMISION_FECHA_INICIO_COBRO.sql; el backoffice no lo notó
-- porque AdminService.listEstudios() tiene un catch que cae a leer la tabla.
create or replace function public.admin_list_studios(p_search text default null)
returns table(id bigint, nombre text, categoria text, categorias text[], barrio text,
  direccion text, descripcion text, foto_url text, instagram text, whatsapp text,
  web text, lat double precision, lng double precision, activo boolean,
  comision_aura numeric, fecha_inicio_cobro date, comision_workshop integer,
  cbu text, tipo_precio text, creditos_min integer, creditos_max integer,
  admin_email text, admin_count bigint, admin_emails text)
language plpgsql security definer set search_path to 'public'
as $function$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  return query
  select
    e.id::bigint,
    e.nombre::text,
    e.categoria::text,
    e.categorias::text[],
    e.barrio::text,
    e.direccion::text,
    e.descripcion::text,
    e.foto_url::text,
    e.instagram::text,
    e.whatsapp::text,
    e.web::text,
    e.lat::double precision,
    e.lng::double precision,
    coalesce(e.activo, true)::boolean,
    coalesce(d.comision_aura, 30)::numeric,
    e.fecha_inicio_cobro::date,
    coalesce(d.comision_workshop, 15)::integer,
    d.cbu::text,
    coalesce(e.tipo_precio, 'rango')::text,
    e.creditos_min::integer,
    e.creditos_max::integer,
    (select u.email::text from public.usuarios u
      where u.estudio_id = e.id and u.rol in ('estudio', 'admin_estudio')
      order by u.email limit 1),
    (select count(*)::bigint from public.usuarios u
      where u.estudio_id = e.id and u.rol in ('estudio', 'admin_estudio')),
    (select string_agg(u.email, ', ' order by u.email)::text from public.usuarios u
      where u.estudio_id = e.id and u.rol in ('estudio', 'admin_estudio'))
  from public.estudios e
  left join public.estudios_datos_cobro d on d.estudio_id = e.id
  where p_search is null
     or e.nombre ilike '%' || p_search || '%'
     or coalesce(e.barrio, '') ilike '%' || p_search || '%'
     or exists (select 1 from unnest(e.categorias) as c where c ilike '%' || p_search || '%')
  order by e.nombre;
end;
$function$;


-- admin_set_comision_workshop: setea SOLO la comisión de workshops.
-- Existe porque comision_workshop pasó a estudios_datos_cobro y el trigger
-- datos_cobro_bloquear_columnas_aura impide que un cliente la escriba directo.
-- Mismo patrón que admin_set_pricing_estudio.
--
-- NO se reusa admin_upsert_estudio: en modo UPDATE asigna barrio/direccion/
-- descripcion/foto_url/instagram/whatsapp/web/lat/lng/fecha_inicio_cobro sin
-- coalesce, así que una llamada parcial le borraría esos campos al estudio.
create or replace function public.admin_set_comision_workshop(
  p_estudio_id bigint,
  p_comision integer)
returns void language plpgsql security definer set search_path to 'public'
as $function$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  if p_comision is null or p_comision < 0 or p_comision > 100 then
    raise exception 'Comisión inválida';
  end if;

  insert into public.estudios_datos_cobro (estudio_id, comision_workshop)
  values (p_estudio_id, p_comision)
  on conflict (estudio_id) do update set comision_workshop = excluded.comision_workshop;

  -- DUAL-WRITE transitorio hasta el paso 8 (DROP de las columnas viejas).
  update public.estudios set comision_workshop = p_comision where id = p_estudio_id;

  perform public.log_admin_action(
    'Editar comisión workshops',
    'Estudio #' || p_estudio_id || ' -> ' || p_comision || '%',
    'pricing');
end;
$function$;

grant execute on function public.admin_set_comision_workshop(bigint, integer) to authenticated;


-- ---------------------------------------------------------------------------
-- CIERRE (aplicado 2026-08-20, en este orden por seguridad)
-- ---------------------------------------------------------------------------
-- OJO CON EL ORDEN: el plan original abría a anon ANTES del DROP. Eso habría
-- dejado una ventana en la que cualquiera con la anon key (que es pública y va
-- en el bundle web) podía pedir estudios?select=cbu. Se invirtió: primero se
-- borran las columnas, después se abre el catálogo.

-- ===========================================================================
-- CIERRE paso A: sacar el DUAL-WRITE de las funciones.
-- Después de esto, cbu/alias/banco/titular/comisiones/valor_credito/dia_pago
-- se escriben SOLO en estudios_datos_cobro. fecha_inicio_cobro sigue en estudios.
-- ===========================================================================

-- 1) admin_upsert_estudio: deja de escribir cbu/comision_aura/comision_workshop
--    en `estudios`. fecha_inicio_cobro SÍ se sigue escribiendo ahí.
create or replace function public.admin_upsert_estudio(
  p_estudio_id bigint default null, p_nombre text default null,
  p_categoria text default null, p_barrio text default null,
  p_direccion text default null, p_descripcion text default null,
  p_foto_url text default null, p_instagram text default null,
  p_whatsapp text default null, p_web text default null,
  p_lat double precision default null, p_lng double precision default null,
  p_activo boolean default true, p_comision numeric default null,
  p_fecha_inicio_cobro date default null, p_comision_workshop integer default null,
  p_cbu text default null, p_tipo_precio text default null,
  p_creditos_min integer default null, p_creditos_max integer default null,
  p_categorias text[] default null)
returns void language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_categorias text[];
  v_id bigint;
  v_cbu text := nullif(trim(coalesce(p_cbu, '')), '');
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  v_categorias := coalesce(
    nullif(
      array(select distinct trim(c) from unnest(coalesce(p_categorias, '{}')) as c
             where trim(coalesce(c, '')) <> ''),
      '{}'),
    case when trim(coalesce(p_categoria, '')) <> ''
         then array[trim(p_categoria)] else '{}' end);

  if p_estudio_id is null then
    insert into public.estudios (
      nombre, categorias, barrio, direccion, descripcion, foto_url,
      instagram, whatsapp, web, lat, lng, activo,
      fecha_inicio_cobro, tipo_precio, creditos_min, creditos_max
    ) values (
      p_nombre, v_categorias, p_barrio, p_direccion, p_descripcion, p_foto_url,
      p_instagram, p_whatsapp, p_web, p_lat, p_lng, coalesce(p_activo, true),
      p_fecha_inicio_cobro,
      coalesce(nullif(trim(coalesce(p_tipo_precio, '')), ''), 'rango'),
      p_creditos_min, p_creditos_max
    ) returning id into v_id;

    perform public.log_admin_action('Crear estudio', coalesce(p_nombre, 'Sin nombre'), 'estudios');
  else
    v_id := p_estudio_id;
    update public.estudios
       set nombre = coalesce(nullif(trim(p_nombre), ''), nombre),
           categorias = case when v_categorias = '{}' then categorias else v_categorias end,
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
           fecha_inicio_cobro = p_fecha_inicio_cobro,
           tipo_precio = coalesce(nullif(trim(coalesce(p_tipo_precio, '')), ''), tipo_precio),
           creditos_min = coalesce(p_creditos_min, creditos_min),
           creditos_max = coalesce(p_creditos_max, creditos_max)
     where id = p_estudio_id;

    perform public.log_admin_action('Editar estudio',
      coalesce(p_nombre, 'Estudio') || ' (#' || p_estudio_id || ')', 'estudios');
  end if;

  -- Único destino de los datos de cobro.
  insert into public.estudios_datos_cobro (
    estudio_id, cbu, comision_aura, comision_workshop
  ) values (
    v_id, v_cbu, coalesce(p_comision, 30), coalesce(p_comision_workshop, 15)
  )
  on conflict (estudio_id) do update
    set cbu               = excluded.cbu,
        comision_aura     = coalesce(p_comision, public.estudios_datos_cobro.comision_aura),
        comision_workshop = coalesce(p_comision_workshop, public.estudios_datos_cobro.comision_workshop);
end;
$function$;


-- 2) admin_set_valor_credito_ars: sin dual-write.
create or replace function public.admin_set_valor_credito_ars(p_value bigint)
returns void language plpgsql security definer set search_path to 'public'
as $function$
begin
  if not exists (select 1 from public.admin_users where user_id = auth.uid()) then
    raise exception 'No autorizado';
  end if;
  if p_value is null or p_value <= 0 then
    raise exception 'El valor debe ser mayor a 0';
  end if;

  insert into public.configuracion_global (clave, valor, updated_at)
  values ('valor_credito_ars', p_value::text, now())
  on conflict (clave) do update set valor = excluded.valor, updated_at = now();

  perform public.recalc_pack_prices();

  update public.estudios_datos_cobro set valor_credito = p_value;
end;
$function$;


-- 3) admin_update_global_credit_value: sin dual-write.
create or replace function public.admin_update_global_credit_value(p_value integer)
returns void language plpgsql security definer set search_path to 'public'
as $function$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  if p_value is null or p_value <= 0 then
    raise exception 'Valor inválido';
  end if;

  update public.estudios_datos_cobro set valor_credito = p_value where true;

  update public.pricing_credit_packs set precio = creditos * p_value where true;
  update public.pricing_planes set precio = creditos * p_value, ahorro = null where true;

  perform public.log_admin_action('Actualizar valor crédito', 'Nuevo valor: $' || p_value, 'config');
end;
$function$;


-- 4) admin_set_comision_workshop: sin dual-write.
create or replace function public.admin_set_comision_workshop(
  p_estudio_id bigint, p_comision integer)
returns void language plpgsql security definer set search_path to 'public'
as $function$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  if p_comision is null or p_comision < 0 or p_comision > 100 then
    raise exception 'Comisión inválida';
  end if;

  insert into public.estudios_datos_cobro (estudio_id, comision_workshop)
  values (p_estudio_id, p_comision)
  on conflict (estudio_id) do update set comision_workshop = excluded.comision_workshop;

  perform public.log_admin_action(
    'Editar comisión workshops',
    'Estudio #' || p_estudio_id || ' -> ' || p_comision || '%',
    'pricing');
end;
$function$;


-- 5) estudios_bloquear_columnas_aura: sacar las columnas que se van.
--    Si no se reescribe ANTES del DROP, cualquier UPDATE sobre `estudios`
--    revienta (plpgsql resuelve new.<col> en tiempo de ejecución).
--    Quedan protegidas: creditos_min, creditos_max, tipo_precio,
--    horarios_config, precio_config y fecha_inicio_cobro.
--    Las que se movieron ahora las protege datos_cobro_bloquear_columnas_aura.
create or replace function public.estudios_bloquear_columnas_aura()
returns trigger language plpgsql set search_path to 'public' as $function$
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if new.creditos_min       is distinct from old.creditos_min
  or new.creditos_max       is distinct from old.creditos_max
  or new.tipo_precio        is distinct from old.tipo_precio
  or new.horarios_config    is distinct from old.horarios_config
  or new.precio_config      is distinct from old.precio_config
  or new.fecha_inicio_cobro is distinct from old.fecha_inicio_cobro then
    raise exception 'Comisiones y precios los define Aura desde el backoffice';
  end if;

  return new;
end;
$function$;


-- ===========================================================================
-- CIERRE paso B: DROP de las columnas de cobro en `estudios`.
-- Cierra definitivamente el leak: a partir de acá `estudios` es solo catálogo.
--
-- PRERREQUISITOS (ya hechos):
--   - estudios_datos_cobro creada, migrada y verificada (0 divergencias)
--   - dual-write removido de las 5 funciones
--   - estudios_bloquear_columnas_aura reescrita sin estas columnas
--   - Dart repuntado + rebuild
--
-- fecha_inicio_cobro NO se toca: se queda en `estudios`.
-- ===========================================================================

alter table public.estudios
  drop column cbu,
  drop column alias,
  drop column banco,
  drop column titular,
  drop column comision_aura,
  drop column comision_workshop,
  drop column valor_credito,
  drop column dia_pago;


-- ---------------------------------------------------------------------------
-- PASO C: abrir el catálogo a invitados (modo visita)
-- ---------------------------------------------------------------------------
alter policy "todos pueden ver estudios" on public.estudios to anon, authenticated;
