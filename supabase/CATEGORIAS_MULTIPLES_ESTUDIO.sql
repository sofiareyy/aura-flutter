-- ============================================================================
-- FEATURE 5 — Un estudio puede tener varias categorias.
-- ============================================================================
--
-- `estudios.categoria` era un unico text. Un estudio real hace Pilates Y
-- Barre Y Yoga, y con el escalar solo aparecia bajo una.
--
-- ESTRATEGIA (sin downtime)
-- Se agrega `categorias text[]` como fuente de verdad y se MANTIENE la
-- columna `categoria` sincronizada con el primer elemento. Asi cualquier
-- query, vista o cliente viejo que lea el escalar sigue funcionando.
-- La sincronizacion la hace un trigger, no el codigo, para que no se
-- desincronice segun quien escriba.
--
-- Idempotente: se puede correr mas de una vez.
-- ============================================================================

begin;

-- ── 1. Nueva columna ───────────────────────────────────────────────────────
alter table public.estudios
  add column if not exists categorias text[] not null default '{}';

comment on column public.estudios.categorias is
  'Categorias del estudio (Pilates, Yoga, Barre, ...). Fuente de verdad. La columna `categoria` se mantiene sincronizada con categorias[1] por trigger, solo para compatibilidad.';

comment on column public.estudios.categoria is
  'DEPRECADA como fuente de verdad: espejo de categorias[1], mantenida por el trigger trg_sync_categoria_estudio. No escribir directo, usar `categorias`.';

-- ── 2. Backfill desde el escalar ───────────────────────────────────────────
update public.estudios
   set categorias = array[trim(categoria)]
 where categorias = '{}'
   and categoria is not null
   and trim(categoria) <> '';

-- ── 3. Trigger de sincronizacion categorias[1] -> categoria ────────────────
create or replace function public.sync_categoria_estudio()
returns trigger
language plpgsql
as $$
begin
  -- Si el caller escribio solo el escalar (cliente viejo) y no toco el
  -- array, sembramos el array desde el escalar en vez de pisarlo con null.
  if (new.categorias is null or new.categorias = '{}')
     and new.categoria is not null and trim(new.categoria) <> '' then
    new.categorias := array[trim(new.categoria)];
  end if;

  new.categoria := case
    when new.categorias is null or array_length(new.categorias, 1) is null
      then null
    else new.categorias[1]
  end;

  return new;
end;
$$;

drop trigger if exists trg_sync_categoria_estudio on public.estudios;

create trigger trg_sync_categoria_estudio
  before insert or update on public.estudios
  for each row execute function public.sync_categoria_estudio();

-- ── 4. Indice GIN para los filtros por categoria ───────────────────────────
-- Sin esto, `categorias @> '{Yoga}'` es un seq scan.
create index if not exists estudios_categorias_gin
  on public.estudios using gin (categorias);

-- ── 5. Catalogo de categorias ──────────────────────────────────────────────
-- `study_categories` es lo que ven los checkboxes. Se insertan las opciones
-- pedidas sin borrar las que el estudio ya venia usando.
insert into public.study_categories (nombre)
select v.nombre
  from (values
    ('Pilates'), ('Yoga'), ('Barre'), ('Gym / Funcional'),
    ('Cerámica'), ('Tufting'), ('Danza'),
    ('Holístico / Bienestar'), ('Meditación'), ('Otro')
  ) as v(nombre)
 where not exists (
   select 1 from public.study_categories sc
    where lower(trim(sc.nombre)) = lower(trim(v.nombre))
 );

-- ── 6. admin_upsert_estudio: aceptar p_categorias ──────────────────────────
-- Se agrega el parametro al final para no romper llamadas posicionales.
-- p_categoria queda como fallback para clientes viejos.
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

  -- Normaliza: usa p_categorias si vino; si no, cae al escalar.
  v_categorias := coalesce(
    nullif(
      array(
        select distinct trim(c)
          from unnest(coalesce(p_categorias, '{}')) as c
         where trim(coalesce(c, '')) <> ''
      ),
      '{}'
    ),
    case
      when trim(coalesce(p_categoria, '')) <> '' then array[trim(p_categoria)]
      else '{}'
    end
  );

  if p_estudio_id is null then
    insert into public.estudios (
      nombre, categorias, barrio, direccion, descripcion,
      foto_url, instagram, whatsapp, web, lat, lng, activo,
      comision_aura, fecha_inicio_cobro, comision_workshop, cbu,
      tipo_precio, creditos_min, creditos_max
    ) values (
      p_nombre, v_categorias, p_barrio, p_direccion, p_descripcion,
      p_foto_url, p_instagram, p_whatsapp, p_web, p_lat, p_lng,
      coalesce(p_activo, true),
      coalesce(p_comision, 30), p_fecha_inicio_cobro,
      coalesce(p_comision_workshop, 15),
      nullif(trim(coalesce(p_cbu, '')), ''),
      coalesce(nullif(trim(coalesce(p_tipo_precio, '')), ''), 'rango'),
      p_creditos_min, p_creditos_max
    );

    perform public.log_admin_action('Crear estudio', coalesce(p_nombre, 'Sin nombre'), 'estudios');
  else
    update public.estudios
       set nombre = coalesce(nullif(trim(p_nombre), ''), nombre),
           -- Si no vino ninguna categoria, no se pisan las existentes.
           categorias = case
             when v_categorias = '{}' then categorias
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
           comision_aura = coalesce(p_comision, comision_aura),
           fecha_inicio_cobro = p_fecha_inicio_cobro,
           comision_workshop = coalesce(p_comision_workshop, comision_workshop),
           cbu = nullif(trim(coalesce(p_cbu, '')), ''),
           tipo_precio = coalesce(nullif(trim(coalesce(p_tipo_precio, '')), ''), tipo_precio),
           creditos_min = coalesce(p_creditos_min, creditos_min),
           creditos_max = coalesce(p_creditos_max, creditos_max)
     where id = p_estudio_id;

    perform public.log_admin_action('Editar estudio', coalesce(p_nombre, 'Estudio') || ' (#' || p_estudio_id || ')', 'estudios');
  end if;
end;
$function$;

-- ── 7. admin_list_studios: devolver categorias ─────────────────────────────
drop function if exists public.admin_list_studios(text);

create or replace function public.admin_list_studios(p_search text default null)
returns table(
  id bigint, nombre text, categoria text, categorias text[], barrio text,
  direccion text, descripcion text, foto_url text, instagram text,
  whatsapp text, web text,
  lat double precision, lng double precision, activo boolean,
  comision_aura numeric, fecha_inicio_cobro date,
  comision_workshop integer, cbu text,
  tipo_precio text, creditos_min integer, creditos_max integer,
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
    e.id, e.nombre, e.categoria, e.categorias, e.barrio, e.direccion,
    e.descripcion, e.foto_url, e.instagram, e.whatsapp, e.web,
    e.lat, e.lng,
    coalesce(e.activo, true) as activo,
    coalesce(e.comision_aura, 30) as comision_aura,
    e.fecha_inicio_cobro,
    coalesce(e.comision_workshop, 15) as comision_workshop,
    e.cbu,
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
  where p_search is null
     or e.nombre ilike '%' || p_search || '%'
     or coalesce(e.barrio, '') ilike '%' || p_search || '%'
     -- Busca en TODAS las categorias, no solo en la principal.
     or exists (
       select 1 from unnest(e.categorias) as c
        where c ilike '%' || p_search || '%'
     )
  order by e.nombre;
end;
$function$;

-- ── 8. RLS: el estudio puede editar sus propias categorias ─────────────────
-- El panel del estudio hace un UPDATE directo sobre `estudios`. Ya existe
-- la policy de datos bancarios; esta la complementa por si no cubria las
-- columnas nuevas. Si tu policy de UPDATE ya es por tabla y no por columna,
-- este bloque no cambia nada.
do $$
begin
  if not exists (
    select 1 from pg_policies
     where schemaname = 'public'
       and tablename = 'estudios'
       and policyname = 'estudio_admin_actualiza_su_estudio'
  ) then
    create policy estudio_admin_actualiza_su_estudio
      on public.estudios for update
      to authenticated
      using (
        exists (
          select 1 from public.estudio_admins ea
           where ea.estudio_id = estudios.id
             and ea.usuario_id = auth.uid()
        )
      )
      with check (
        exists (
          select 1 from public.estudio_admins ea
           where ea.estudio_id = estudios.id
             and ea.usuario_id = auth.uid()
        )
      );
  end if;
end $$;

commit;

-- ── VERIFICACION ───────────────────────────────────────────────────────────
-- Ningun estudio deberia quedar sin categorias:
-- select id, nombre, categoria, categorias
--   from public.estudios where categorias = '{}';
--
-- El escalar tiene que coincidir siempre con el primer elemento:
-- select id, nombre, categoria, categorias[1]
--   from public.estudios
--  where categoria is distinct from categorias[1];
