-- ############################################################################
-- AURA — TANDAS A + B (correr entero, de arriba a abajo)
-- ############################################################################
--
-- Son DOS transacciones separadas a proposito: si la parte B falla, la A
-- queda igual aplicada y no hay que rehacerla.
--
-- PARTE A — rol profe, ventana de gracia del QR, tope de cancelacion, grilla
-- PARTE B — categorias: CRUD desde backoffice, multiples por clase, y
--           desacople del precio respecto de la categoria
--
-- Todo es idempotente: se puede correr mas de una vez.
-- ############################################################################


-- ============================================================================
-- TANDA A — Rol profe, ventana de gracia del QR, tope de cancelacion, grilla
-- ============================================================================
-- Idempotente. Correr entero.
-- ============================================================================

begin;

-- ══════════════════════════════════════════════════════════════════════════
-- BUG B.2 — El rol real es por estudio, no global
-- ══════════════════════════════════════════════════════════════════════════
-- `usuarios.rol` es global (uno por persona) pero el permiso real vive en
-- `estudio_admins.rol` (uno por estudio). La app entera lee el global, asi
-- que alguien admin en el estudio A y profe en el B entraba al B con panel
-- de admin completo.
--
-- Se sincroniza el global con el del estudio activo en los dos momentos en
-- que puede cambiar: al cambiar de estudio y al ser dada de alta como profe.
-- Nunca se toca a un admin de Aura ('admin'): ese rol es de otra dimension.

-- drop previo: la version deployada puede tener otro tipo de retorno y
-- `create or replace` no puede cambiarlo.
drop function if exists public.set_active_estudio(int);

create or replace function public.set_active_estudio(p_estudio_id int)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id  uuid := auth.uid();
  v_authorized boolean;
  v_rol_estudio text;
  v_rol_global  text;
begin
  if v_caller_id is null then
    return json_build_object('ok', false, 'error', 'no_auth');
  end if;

  select exists (
    select 1 from public.estudio_admins
     where estudio_id = p_estudio_id
       and usuario_id = v_caller_id
  ) into v_authorized;

  if not v_authorized then
    return json_build_object('ok', false, 'error', 'forbidden');
  end if;

  select rol into v_rol_estudio
    from public.estudio_admins
   where estudio_id = p_estudio_id
     and usuario_id = v_caller_id;

  select rol into v_rol_global
    from public.usuarios
   where id = v_caller_id;

  update public.usuarios
     set estudio_id = p_estudio_id,
         -- Espeja el rol del estudio que se activa. Sin esto el gating de
         -- la app (router + sidebar) leia un rol que no correspondia al
         -- estudio activo.
         rol = case
           when v_rol_global = 'admin' then v_rol_global
           when v_rol_estudio is null then rol
           else v_rol_estudio
         end
   where id = v_caller_id;

  return json_build_object(
    'ok', true,
    'rol', coalesce(v_rol_estudio, v_rol_global)
  );
end;
$$;

grant execute on function public.set_active_estudio(int) to authenticated;


-- studio_add_profe: antes solo ponia rol='profe' si el global era exactamente
-- 'usuario'. Si era 'estudio', 'admin_estudio' o NULL quedaba como estaba y
-- la persona seguia viendo el panel completo.
drop function if exists public.studio_add_profe(int, text);

create or replace function public.studio_add_profe(
  p_estudio_id int,
  p_email text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id       uuid := auth.uid();
  v_authorized      boolean;
  v_target_id       uuid;
  v_normalized_email text := lower(trim(coalesce(p_email, '')));
begin
  if v_caller_id is null then
    return json_build_object('ok', false, 'error', 'no_auth');
  end if;

  -- Solo un admin del estudio (no otra profe) puede dar de alta profes.
  select exists (
    select 1 from public.estudio_admins
     where estudio_id = p_estudio_id
       and usuario_id = v_caller_id
       and rol in ('estudio', 'admin_estudio')
  ) into v_authorized;

  if not v_authorized then
    return json_build_object('ok', false, 'error', 'forbidden');
  end if;

  if v_normalized_email = '' then
    return json_build_object('ok', false, 'error', 'email_required');
  end if;

  select id into v_target_id
    from public.usuarios
   where lower(trim(email)) = v_normalized_email
   limit 1;

  if v_target_id is null then
    return json_build_object('ok', false, 'error', 'user_not_found');
  end if;

  insert into public.estudio_admins (estudio_id, usuario_id, rol)
  values (p_estudio_id, v_target_id, 'profe')
  on conflict (estudio_id, usuario_id) do nothing;

  -- Si el estudio que se le asigna pasa a ser el activo, el rol global tiene
  -- que reflejarlo. No degradamos a un admin de Aura.
  update public.usuarios
     set rol = 'profe'
   where id = v_target_id
     and coalesce(rol, 'usuario') <> 'admin'
     and (estudio_id is null or estudio_id = p_estudio_id);

  update public.usuarios
     set estudio_id = p_estudio_id
   where id = v_target_id
     and estudio_id is null;

  return json_build_object('ok', true, 'user_id', v_target_id);
end;
$$;

grant execute on function public.studio_add_profe(int, text) to authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- BUG B.3 — RLS de reservas: la profe leia TODA la caja del estudio
-- ══════════════════════════════════════════════════════════════════════════
-- Las policies anteriores daban SELECT/UPDATE a cualquier fila de
-- estudio_admins SIN filtrar rol, asi que una profe podia leer todas las
-- reservas del estudio por API (los datos de Cobros) aunque la UI se lo
-- ocultara.
--
-- A1: la profe puede ver y tomar asistencia en TODAS las clases de los
-- estudios donde esta vinculada. Se descarto acotarla a las clases donde
-- figura como instructora: `clases.instructor` es texto libre y el match
-- por nombre se rompe con cualquier diferencia de tipeo, dejandola sin
-- poder tomar asistencia.
--
-- Lo que la profe NO puede sigue estando cubierto por la UI y el router
-- (cobros, configuracion, crear/editar/eliminar/avisar). El limite de esta
-- policy es que una profe con acceso directo a la API igual podria leer las
-- reservas del estudio; es el precio de que Asistencia funcione siempre.

-- Las policies dependen de esta funcion: se dropean primero para poder
-- reemplazarla, y se recrean mas abajo.
drop policy if exists "estudio lee reservas de sus clases" on public.reservas;
drop policy if exists "estudio actualiza reservas de sus clases" on public.reservas;
drop function if exists public.puede_ver_reservas_de_clase(bigint);

create or replace function public.puede_ver_reservas_de_clase(p_clase_id bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.clases c
      join public.estudio_admins ea
        on ea.estudio_id = c.estudio_id
       and ea.usuario_id = auth.uid()
     where c.id = p_clase_id
  );
$$;

grant execute on function public.puede_ver_reservas_de_clase(bigint)
  to authenticated;

drop policy if exists "estudio lee reservas de sus clases" on public.reservas;
create policy "estudio lee reservas de sus clases"
  on public.reservas for select
  using (public.puede_ver_reservas_de_clase(reservas.clase_id));

drop policy if exists "estudio actualiza reservas de sus clases" on public.reservas;
create policy "estudio actualiza reservas de sus clases"
  on public.reservas for update
  using (public.puede_ver_reservas_de_clase(reservas.clase_id))
  with check (public.puede_ver_reservas_de_clase(reservas.clase_id));


-- ══════════════════════════════════════════════════════════════════════════
-- BUG A — El cron de completar reservas rompia el QR
-- ══════════════════════════════════════════════════════════════════════════
-- asistencia_screen matchea el QR con estado='confirmada'. El cron pasaba la
-- reserva a 'completada' apenas terminaba la clase, asi que escanear a un
-- rezagado 10 minutos despues fallaba con "no esta en estado confirmada".
-- Se agrega una ventana de gracia de 3 horas.

drop function if exists public.completar_reservas_vencidas();

create or replace function public.completar_reservas_vencidas()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ahora timestamp := (
    now() at time zone 'America/Argentina/Buenos_Aires'
  );
  v_gracia interval := interval '3 hours';
  v_completadas int := 0;
begin
  with vencidas as (
    select r.id
      from public.reservas r
      join public.clases c on c.id = r.clase_id
     where r.estado in ('confirmada', 'presente')
       and c.fecha is not null
       and c.fecha
           + make_interval(mins => coalesce(c.duracion_min, 60))
           + v_gracia
           < v_ahora
  )
  update public.reservas r
     set estado = 'completada'
    from vencidas v
   where r.id = v.id;

  get diagnostics v_completadas = row_count;

  return json_build_object(
    'completadas', v_completadas,
    'corrido_a', v_ahora,
    'gracia_horas', 3
  );
end;
$$;

grant execute on function public.completar_reservas_vencidas() to service_role;


-- ══════════════════════════════════════════════════════════════════════════
-- FIX 1 — La cancelacion no puede pasar de 12 hs
-- ══════════════════════════════════════════════════════════════════════════
-- El estudio puede ACORTAR la ventana, nunca estirarla. Antes el RPC y la
-- constraint permitian hasta 7 dias y el stepper hasta 48 hs.

-- Primero normalizamos lo que ya este por encima, si no el ALTER falla.
update public.estudios
   set cancelacion_cierre_minutos = 720
 where cancelacion_cierre_minutos > 720;

update public.clases
   set cancelacion_cierre_minutos = 720
 where cancelacion_cierre_minutos > 720;

update public.horarios_fijos
   set cancelacion_cierre_minutos = 720
 where cancelacion_cierre_minutos > 720;

-- A2: el cierre de RESERVAS topea en 48 hs (2880 min), que es lo que ya
-- permitia el stepper. La constraint estaba en 7 dias y quedaba desalineada.
update public.estudios
   set reserva_cierre_minutos = 2880
 where reserva_cierre_minutos > 2880;

update public.clases
   set reserva_cierre_minutos = 2880
 where reserva_cierre_minutos > 2880;

update public.horarios_fijos
   set reserva_cierre_minutos = 2880
 where reserva_cierre_minutos > 2880;

alter table public.estudios
  drop constraint if exists estudios_cierres_rango_check;

alter table public.estudios
  add constraint estudios_cierres_rango_check
  check (
    reserva_cierre_minutos between 0 and 2880
    and cancelacion_cierre_minutos between 0 and 720
  );

drop function if exists public.set_estudio_cierres(int, int, int);

create or replace function public.set_estudio_cierres(
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
  v_ok  boolean;
begin
  if v_uid is null then
    return json_build_object('ok', false, 'error', 'No autenticado');
  end if;

  -- Solo admin del estudio. Una profe no configura nada.
  select exists (
    select 1 from public.estudio_admins
     where estudio_id = p_estudio_id
       and usuario_id = v_uid
       and rol in ('estudio', 'admin_estudio')
  ) into v_ok;

  if not v_ok then
    return json_build_object('ok', false, 'error', 'Sin permisos');
  end if;

  -- Cierre de reservas: hasta 48 hs antes (A2).
  if p_reserva_cierre_minutos is null
     or p_cancelacion_cierre_minutos is null
     or p_reserva_cierre_minutos not between 0 and 2880 then
    return json_build_object('ok', false, 'error', 'Fuera de rango');
  end if;

  -- Tope duro de la politica: 720 min = 12 hs.
  if p_cancelacion_cierre_minutos not between 0 and 720 then
    return json_build_object(
      'ok', false,
      'error', 'La cancelacion no puede superar las 12 horas'
    );
  end if;

  update public.estudios
     set reserva_cierre_minutos = p_reserva_cierre_minutos,
         cancelacion_cierre_minutos = p_cancelacion_cierre_minutos
   where id = p_estudio_id;

  return json_build_object(
    'ok', true,
    'reserva_cierre_minutos', p_reserva_cierre_minutos,
    'cancelacion_cierre_minutos', p_cancelacion_cierre_minutos
  );
end;
$$;

grant execute on function public.set_estudio_cierres(int, int, int)
  to authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- FIX 8 — Grilla a 63 dias (9 semanas)
-- ══════════════════════════════════════════════════════════════════════════
-- El boton del panel generaba 13 semanas y el cron nocturno mantenia 4: el
-- estudio veia una ventana y el cron otra. Ambos pasan a 9 semanas.

-- Cuerpo IDENTICO al de CRON_GRILLAS_Y_LISTA_ESPERA.sql; lo unico que cambia
-- es el default de p_weeks (4 -> 9).
drop function if exists public.generar_clases_todos_estudios(int);

create or replace function public.generar_clases_todos_estudios(
  p_weeks int default 9
) returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_estudio_id     int;
  v_res            json;
  v_estudios       int := 0;
  v_total_creadas  int := 0;
  v_total_omitidas int := 0;
begin
  for v_estudio_id in
    select distinct estudio_id
      from public.horarios_fijos
     where coalesce(activo, true) = true
  loop
    v_res := public.generar_clases_estudio(v_estudio_id, p_weeks);
    v_total_creadas  := v_total_creadas  + coalesce((v_res->>'creadas')::int, 0);
    v_total_omitidas := v_total_omitidas + coalesce((v_res->>'omitidas')::int, 0);
    v_estudios := v_estudios + 1;
  end loop;

  return json_build_object(
    'estudios', v_estudios,
    'creadas',  v_total_creadas,
    'omitidas', v_total_omitidas
  );
end;
$$;

grant execute on function public.generar_clases_todos_estudios(int)
  to authenticated, service_role;

-- NO reprogramamos el cron 'regenerar-grillas-diario' a proposito: esta
-- agendado desde el dashboard con PROJECT_REF / ANON_KEY / CRON_SECRET que
-- no estan en el repo, y re-emitirlo aca lo romperia. Ese cron manda
-- `weeks: 4` en el body; la Edge Function `regenerar-grillas` ahora aplica
-- un piso de 9 semanas, asi que la ventana queda en 63 dias sin tocarlo.

commit;

-- ── VERIFICACION (correr aparte) ───────────────────────────────────────────
-- select conname, pg_get_constraintdef(oid)
--   from pg_constraint where conname = 'estudios_cierres_rango_check';
--
-- select id, nombre, reserva_cierre_minutos, cancelacion_cierre_minutos
--   from public.estudios order by nombre;
--
-- select jobname, schedule from cron.job order by jobname;
--
-- select policyname, cmd from pg_policies
--  where tablename = 'reservas' order by policyname;
--
-- Roles desalineados entre global y por-estudio:
-- select u.email, u.rol as rol_global, ea.rol as rol_estudio, ea.estudio_id
--   from public.usuarios u
--   join public.estudio_admins ea
--     on ea.usuario_id = u.id and ea.estudio_id = u.estudio_id
--  where u.rol is distinct from ea.rol and u.rol <> 'admin';

-- ############################################################################
-- ##                        FIN PARTE A / INICIO PARTE B                    ##
-- ############################################################################


-- ============================================================================
-- TANDA B — Categorias: fuente unica, CRUD completo, multiples por clase
-- ============================================================================
-- Idempotente. Correr entero.
-- ============================================================================

begin;

-- ══════════════════════════════════════════════════════════════════════════
-- FIX 2 — Catalogo de categorias con CRUD real
-- ══════════════════════════════════════════════════════════════════════════
-- La tabla se creo desde el dashboard y nunca estuvo versionada, igual que
-- los RPC que la manejan (add/rename/delete solo existian compilados en el
-- bundle web). Se define todo aca.

create table if not exists public.study_categories (
  id     bigint generated by default as identity primary key,
  nombre text not null,
  activa boolean not null default true,
  created_at timestamptz not null default now()
);

-- Por si la tabla ya existia sin estas columnas.
alter table public.study_categories
  add column if not exists activa boolean not null default true;

create unique index if not exists study_categories_nombre_uniq
  on public.study_categories (lower(trim(nombre)));

comment on column public.study_categories.activa is
  'Categoria disponible para asignar. Desactivar la saca de los selectores sin borrar el historial de las clases que ya la usan.';

alter table public.study_categories enable row level security;

-- Lectura publica: la app la necesita para los filtros del usuario.
drop policy if exists "study_categories select" on public.study_categories;
create policy "study_categories select"
  on public.study_categories for select
  using (true);

-- Escritura: solo por los RPC (security definer). Sin policies de escritura,
-- ni anon ni authenticated pueden tocarla directo.


-- ── RPC: listar ────────────────────────────────────────────────────────────
drop function if exists public.admin_list_studio_categories();

create or replace function public.admin_list_studio_categories()
returns table(id bigint, nombre text, activa boolean, en_uso bigint)
language sql
stable
security definer
set search_path = public
as $$
  select
    sc.id,
    sc.nombre,
    sc.activa,
    -- Cuantos estudios la tienen asignada: sirve para avisar antes de borrar.
    (select count(*)
       from public.estudios e
      where sc.nombre = any(e.categorias)) as en_uso
  from public.study_categories sc
  order by sc.activa desc, sc.nombre;
$$;

grant execute on function public.admin_list_studio_categories() to authenticated;


-- ── RPC: crear ─────────────────────────────────────────────────────────────
drop function if exists public.admin_add_studio_category(text);

create or replace function public.admin_add_studio_category(p_nombre text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nombre text := trim(coalesce(p_nombre, ''));
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  if v_nombre = '' then
    return json_build_object('ok', false, 'error', 'El nombre no puede estar vacio');
  end if;

  if exists (
    select 1 from public.study_categories
     where lower(trim(nombre)) = lower(v_nombre)
  ) then
    return json_build_object('ok', false, 'error', 'Ya existe una categoria con ese nombre');
  end if;

  insert into public.study_categories (nombre, activa)
  values (v_nombre, true);

  return json_build_object('ok', true, 'nombre', v_nombre);
end;
$$;

grant execute on function public.admin_add_studio_category(text) to authenticated;


-- ── RPC: renombrar ─────────────────────────────────────────────────────────
-- Propaga el nombre nuevo a estudios.categorias, clases.categorias y
-- horarios_fijos.categorias, si no las asignaciones quedan colgadas.
-- La version vieja usaba p_old_name/p_new_name: se dropea por firma.
drop function if exists public.admin_rename_studio_category(text, text);

create or replace function public.admin_rename_studio_category(
  p_actual text,
  p_nuevo  text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actual text := trim(coalesce(p_actual, ''));
  v_nuevo  text := trim(coalesce(p_nuevo, ''));
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  if v_actual = '' or v_nuevo = '' then
    return json_build_object('ok', false, 'error', 'Nombres invalidos');
  end if;

  if exists (
    select 1 from public.study_categories
     where lower(trim(nombre)) = lower(v_nuevo)
       and lower(trim(nombre)) <> lower(v_actual)
  ) then
    return json_build_object('ok', false, 'error', 'Ya existe una categoria con ese nombre');
  end if;

  update public.study_categories
     set nombre = v_nuevo
   where lower(trim(nombre)) = lower(v_actual);

  update public.estudios
     set categorias = array_replace(categorias, v_actual, v_nuevo)
   where v_actual = any(categorias);

  update public.clases
     set categorias = array_replace(categorias, v_actual, v_nuevo)
   where v_actual = any(categorias);

  update public.horarios_fijos
     set categorias = array_replace(categorias, v_actual, v_nuevo)
   where v_actual = any(categorias);

  return json_build_object('ok', true, 'nombre', v_nuevo);
end;
$$;

grant execute on function public.admin_rename_studio_category(text, text)
  to authenticated;


-- ── RPC: activar / desactivar ──────────────────────────────────────────────
-- Preferible a borrar: saca la categoria de los selectores pero no toca las
-- clases que ya la tienen asignada.
drop function if exists public.admin_toggle_studio_category(text, boolean);

create or replace function public.admin_toggle_studio_category(
  p_nombre text,
  p_activa boolean
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nombre text := trim(coalesce(p_nombre, ''));
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  update public.study_categories
     set activa = coalesce(p_activa, true)
   where lower(trim(nombre)) = lower(v_nombre);

  if not found then
    return json_build_object('ok', false, 'error', 'Categoria no encontrada');
  end if;

  return json_build_object('ok', true, 'nombre', v_nombre, 'activa', p_activa);
end;
$$;

grant execute on function public.admin_toggle_studio_category(text, boolean)
  to authenticated;


-- ── RPC: eliminar ──────────────────────────────────────────────────────────
-- Borra la categoria y la saca de todas las asignaciones.
drop function if exists public.admin_delete_studio_category(text);

create or replace function public.admin_delete_studio_category(p_nombre text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nombre text := trim(coalesce(p_nombre, ''));
  v_afectados int := 0;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  delete from public.study_categories
   where lower(trim(nombre)) = lower(v_nombre);

  update public.estudios
     set categorias = array_remove(categorias, v_nombre)
   where v_nombre = any(categorias);
  get diagnostics v_afectados = row_count;

  update public.clases
     set categorias = array_remove(categorias, v_nombre)
   where v_nombre = any(categorias);

  update public.horarios_fijos
     set categorias = array_remove(categorias, v_nombre)
   where v_nombre = any(categorias);

  return json_build_object('ok', true, 'estudios_afectados', v_afectados);
end;
$$;

grant execute on function public.admin_delete_studio_category(text)
  to authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- FIX 3 — Multiples categorias por clase y por horario fijo (max 5)
-- ══════════════════════════════════════════════════════════════════════════
-- Mismo patron que estudios: columna nueva text[] como fuente de verdad y el
-- escalar `categoria` sincronizado por trigger, para no romper lo legacy.

alter table public.clases
  add column if not exists categorias text[] not null default '{}';

alter table public.horarios_fijos
  add column if not exists categorias text[] not null default '{}';

-- Backfill desde el escalar.
update public.clases
   set categorias = array[trim(categoria)]
 where categorias = '{}'
   and categoria is not null
   and trim(categoria) <> '';

update public.horarios_fijos
   set categorias = array[trim(categoria)]
 where categorias = '{}'
   and categoria is not null
   and trim(categoria) <> '';

-- Trigger compartido: valida el tope de 5 y sincroniza el escalar.
create or replace function public.sync_categorias_clase()
returns trigger
language plpgsql
as $$
begin
  -- Cliente viejo que solo mando el escalar: sembramos el array.
  if (new.categorias is null or new.categorias = '{}')
     and new.categoria is not null
     and trim(new.categoria) <> '' then
    new.categorias := array[trim(new.categoria)];
  end if;

  if new.categorias is not null
     and array_length(new.categorias, 1) > 5 then
    raise exception 'Maximo 5 categorias por clase (recibidas %)',
      array_length(new.categorias, 1);
  end if;

  new.categoria := case
    when new.categorias is null
      or array_length(new.categorias, 1) is null
    then null
    else new.categorias[1]
  end;

  return new;
end;
$$;

drop trigger if exists trg_sync_categorias_clase on public.clases;
create trigger trg_sync_categorias_clase
  before insert or update on public.clases
  for each row execute function public.sync_categorias_clase();

drop trigger if exists trg_sync_categorias_horario on public.horarios_fijos;
create trigger trg_sync_categorias_horario
  before insert or update on public.horarios_fijos
  for each row execute function public.sync_categorias_clase();

create index if not exists clases_categorias_gin
  on public.clases using gin (categorias);

create index if not exists horarios_fijos_categorias_gin
  on public.horarios_fijos using gin (categorias);


-- ══════════════════════════════════════════════════════════════════════════
-- DESACOPLAR PRECIO DE CATEGORIA
-- ══════════════════════════════════════════════════════════════════════════
-- El precio de una clase sale del valor propio del estudio (fijo o rango)
-- que define el admin, nunca de la categoria. `calcular_precio_clase` (v3)
-- ya ignoraba p_categoria; lo que quedaba era que generar_clases_estudio
-- buscara la categoria del estudio solo para pasarsela. Se saca ese lookup
-- y ademas se propagan las categorias del horario fijo a la clase.

-- drop previo: la version deployada tiene otro default (4 o 13) y puede
-- tener otro tipo de retorno; `create or replace` no puede cambiarlo.
drop function if exists public.generar_clases_estudio(int, int);

create or replace function public.generar_clases_estudio(
  p_estudio_id int,
  p_weeks int default 9
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now          timestamp := (
    now() at time zone 'America/Argentina/Buenos_Aires'
  );
  v_week_start   date;
  v_week_offset  int;
  v_h            record;
  v_creadas      int := 0;
  v_omitidas     int := 0;
  v_fecha        timestamp;
  v_hora         int;
  v_minuto       int;
  v_hora_text    text;
  v_existente_id int;
  v_resultado    json;
  v_creditos     int;
  v_tipo         text;
begin
  v_week_start := v_now::date - ((extract(isodow from v_now)::int) - 1);

  for v_h in
    select * from public.horarios_fijos
     where estudio_id = p_estudio_id
       and coalesce(activo, true) = true
  loop
    if v_h.dia_semana is null
       or v_h.dia_semana < 1
       or v_h.dia_semana > 7 then
      v_omitidas := v_omitidas + 1;
      continue;
    end if;

    if v_h.nombre is null or trim(v_h.nombre) = '' then
      v_omitidas := v_omitidas + 1;
      continue;
    end if;

    v_hora   := coalesce(extract(hour from v_h.hora_inicio)::int, 8);
    v_minuto := coalesce(extract(minute from v_h.hora_inicio)::int, 0);
    v_hora_text := lpad(v_hora::text, 2, '0')
                   || ':'
                   || lpad(v_minuto::text, 2, '0');

    -- p_categoria = null: el precio NO depende de la categoria.
    v_resultado := public.calcular_precio_clase(
      p_estudio_id,
      null,
      v_h.dia_semana,
      v_hora_text
    );
    v_creditos := (v_resultado->>'creditos')::int;
    v_tipo := v_resultado->>'tipo';

    for v_week_offset in 0..(p_weeks - 1) loop
      v_fecha := (
        v_week_start + (v_week_offset * 7 + (v_h.dia_semana - 1))
      )::timestamp
      + make_interval(hours => v_hora, mins => v_minuto);

      select id into v_existente_id
        from public.clases
       where estudio_id = p_estudio_id
         and horario_fijo_id = v_h.id
         and fecha between v_fecha - interval '1 hour'
                       and v_fecha + interval '1 hour'
       limit 1;

      if v_existente_id is not null then
        v_omitidas := v_omitidas + 1;
        continue;
      end if;

      insert into public.clases (
        estudio_id, horario_fijo_id, nombre, instructor,
        instructor_descripcion, incluye, imagen_url, imagen_ajuste,
        galeria_urls, fecha, duracion_min, lugares_total,
        lugares_disponibles, creditos, reserva_cierre_minutos,
        cancelacion_cierre_minutos, categorias, sala, tipo_precio
      ) values (
        p_estudio_id, v_h.id, v_h.nombre, v_h.instructor,
        v_h.instructor_descripcion, v_h.incluye, v_h.imagen_url,
        v_h.imagen_ajuste, v_h.galeria_urls, v_fecha,
        coalesce(v_h.duracion_min, 60),
        coalesce(v_h.lugares_total, 12),
        coalesce(v_h.lugares_total, 12),
        v_creditos,
        v_h.reserva_cierre_minutos,
        v_h.cancelacion_cierre_minutos,
        coalesce(v_h.categorias, '{}'),
        v_h.sala, v_tipo
      );
      v_creadas := v_creadas + 1;
    end loop;
  end loop;

  return json_build_object('creadas', v_creadas, 'omitidas', v_omitidas);
end;
$$;

grant execute on function public.generar_clases_estudio(int, int)
  to authenticated, service_role;


-- `creditos_por_categoria` queda obsoleta: el precio no se deriva de la
-- categoria. La dejamos en configuracion_global por si hay que auditarla,
-- pero el codigo Dart que la leia se elimina en esta misma tanda.
drop function if exists public.admin_set_creditos_por_categoria(text);

commit;

-- ── VERIFICACION (correr aparte) ───────────────────────────────────────────
-- select nombre, activa from public.study_categories order by activa desc, nombre;
--
-- select count(*) filter (where categorias = '{}') as sin_categoria,
--        count(*) filter (where array_length(categorias,1) > 1) as multi,
--        count(*) as total
--   from public.clases;
--
-- select proname from pg_proc
--  where proname like 'admin_%studio_categor%' order by proname;
