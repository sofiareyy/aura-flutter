-- ============================================================================
-- SERVICIOS DE PRECIO FIJO — Tanda D, mitad de BASE
-- Diseño 100% cerrado en supabase/pendientes/SERVICIOS_PRECIO_FIJO_relevamiento.md
-- (9 decisiones, sección 6c). Este archivo es el "Paso 1" completo, en orden.
--
-- ES ADITIVO: la tabla nueva arranca vacía, así que NINGÚN estudio actual
-- cambia de precio hasta que Aura cree una fila a propósito. La verificación
-- obligatoria es que recalcular todo dé IDÉNTICO (huellas md5 tomadas antes).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1 · EL CHECK VA PRIMERO. Sin 'servicio' acá, el primer guardado revienta
--     con 23514 y el estudio ve un error crudo.
-- ----------------------------------------------------------------------------
alter table public.clases drop constraint clases_tipo_precio_check;
alter table public.clases add constraint clases_tipo_precio_check
  check (tipo_precio = any (array['pico','valle','normal','experiencia','servicio']));

-- ----------------------------------------------------------------------------
-- 2 · La tabla puente. El NOMBRE del servicio es global (study_categories);
--     el PRECIO es por estudio ("Sauna" vale 14 en uno y 18 en otro).
--     `creditos >= 0`: el 0 es deliberado — precio 0 = clase gratis (running
--     club), mismo mecanismo, decisión cerrada.
-- ----------------------------------------------------------------------------
create table if not exists public.estudio_servicios_precio (
  estudio_id bigint  not null references public.estudios(id) on delete cascade,
  servicio   text    not null,
  creditos   integer not null check (creditos >= 0 and creditos <= 500),
  activo     boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (estudio_id, servicio)
);

comment on table public.estudio_servicios_precio is
  'Precio fijo por (estudio, servicio/categoría). Si hay fila activa, la clase con esa categoría vale eso SIEMPRE, sin valle/pico (tipo_precio=''servicio''). Tabla vacía = nada cambia. creditos=0 es válido: clase gratis.';

alter table public.estudio_servicios_precio enable row level security;

-- Lectura: el estudio ve SUS servicios (el panel del build 27 los va a leer).
-- Escritura: nadie desde el cliente; sólo la RPC admin (security definer).
drop policy if exists servicios_precio_select_miembro on public.estudio_servicios_precio;
create policy servicios_precio_select_miembro on public.estudio_servicios_precio
  for select to authenticated
  using (public.es_miembro_de_estudio(estudio_id));

grant select on public.estudio_servicios_precio to authenticated;
grant all    on public.estudio_servicios_precio to service_role;

-- ----------------------------------------------------------------------------
-- 3 · El helper: de un array de categorías, el servicio de precio fijo que
--     aplica. Devuelve NULL si ninguna tiene precio fijo (⇒ camino de hoy),
--     y LEVANTA EXCEPCIÓN si dos o más lo tienen (decisión 2: rechazar, nunca
--     "gana la primera" — el array se arma en el orden en que se tilda y esa
--     precedencia sería invisible). Como lo llaman los triggers BEFORE de
--     precio, el raise aborta el guardado: ese ES el rechazo del plan (ítem 6),
--     y vale para cualquier camino que escriba (app, SQL, backoffice).
--
--     SECURITY DEFINER: los triggers de precio son invoker y el caller
--     (estudio) no necesita permisos propios sobre la tabla para que el
--     cálculo funcione.
-- ----------------------------------------------------------------------------
create or replace function public.servicio_precio_fijo(
  p_estudio_id bigint,
  p_categorias text[]
) returns table (servicio text, creditos integer)
language plpgsql
stable
security definer
set search_path to 'public'
as $$
declare
  v_matches int;
  v_lista   text;
begin
  if p_estudio_id is null or p_categorias is null or cardinality(p_categorias) = 0 then
    return;
  end if;

  select count(*),
         string_agg(esp.servicio || ' (' || esp.creditos || ' cr)', ' y ' order by esp.servicio)
    into v_matches, v_lista
    from public.estudio_servicios_precio esp
   where esp.estudio_id = p_estudio_id
     and esp.activo
     and esp.servicio = any (p_categorias);

  if v_matches >= 2 then
    raise exception 'Elegiste dos servicios con precio fijo: %. Dejá uno solo, o pedile a Aura una categoría combinada.', v_lista
      using errcode = 'P0001';
  end if;

  if v_matches = 1 then
    return query
      select esp.servicio, esp.creditos
        from public.estudio_servicios_precio esp
       where esp.estudio_id = p_estudio_id
         and esp.activo
         and esp.servicio = any (p_categorias);
  end if;
end;
$$;

revoke execute on function public.servicio_precio_fijo(bigint, text[]) from public, anon;
grant  execute on function public.servicio_precio_fijo(bigint, text[]) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 4 · El early return en calcular_precio_clase. p_categoria SIEMPRE existió en
--     la firma y se ignoraba; ahora, si esa categoría tiene precio fijo para
--     ese estudio, devuelve ese precio con tipo='servicio' y NO sigue.
--     Nota decisión 4: el return va ANTES del chequeo de "falta configurar el
--     precio" ⇒ un estudio sólo-spa sin valle/pico puede cargar igual.
--     Si p_categoria es null o no tiene precio fijo ⇒ el resto es BYTE POR
--     BYTE la lógica de hoy.
-- ----------------------------------------------------------------------------
create or replace function public.calcular_precio_clase(
  p_estudio_id bigint, p_categoria text, p_dia integer, p_hora text
) returns json
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_tipo_estudio text;
  v_modo         text;
  v_min          int;
  v_max          int;
  v_config       jsonb;
  v_horarios     jsonb;
  v_hora         int;
  v_es_valle     boolean := false;
  v_serv_cred    int;
begin
  -- SERVICIO DE PRECIO FIJO (2026-08-27): si la categoría tiene precio fijo
  -- para este estudio, ese es el precio, sin franja. Va antes que todo,
  -- incluido el "falta configurar": un estudio sólo-servicios no tiene rango
  -- y no lo necesita.
  if p_categoria is not null and trim(p_categoria) <> '' then
    select esp.creditos into v_serv_cred
      from public.estudio_servicios_precio esp
     where esp.estudio_id = p_estudio_id
       and esp.servicio = p_categoria
       and esp.activo;
    if found then
      return json_build_object('creditos', v_serv_cred, 'tipo', 'servicio', 'ok', true);
    end if;
  end if;

  select coalesce(e.tipo_estudio, 'fitness'),
         coalesce(e.tipo_precio, 'fijo'),
         e.creditos_min, e.creditos_max, e.precio_config, e.horarios_config
    into v_tipo_estudio, v_modo, v_min, v_max, v_config, v_horarios
    from public.estudios e
   where e.id = p_estudio_id;

  if not found then
    return json_build_object('creditos', null, 'tipo', 'normal', 'ok', false);
  end if;

  v_min := coalesce(v_min, (nullif(v_config ->> 'min', '')::numeric)::int);
  v_max := coalesce(v_max, (nullif(v_config ->> 'max', '')::numeric)::int, v_min);

  if v_min is null then
    return json_build_object('creditos', null, 'tipo', 'normal', 'ok', false);
  end if;
  if v_max is null or v_max < v_min then
    v_max := v_min;
  end if;

  if v_tipo_estudio = 'experiencia' then
    return json_build_object('creditos', v_min, 'tipo', 'experiencia', 'ok', true);
  end if;

  -- MODO FIJO: un único precio, sin importar el horario.
  if v_modo <> 'rango' then
    return json_build_object('creditos', v_min, 'tipo', 'normal', 'ok', true);
  end if;

  -- MODO RANGO.
  -- Hora en punto hacia abajo: '8:30' y '8:45' caen en la franja 8; '9:15' en
  -- la 9. split_part sobre ':' ya descarta los minutos, que es el floor.
  v_hora := coalesce(
    nullif(split_part(coalesce(p_hora, '08:00'), ':', 1), '')::int,
    8
  );
  if v_hora < 0 or v_hora > 23 then
    v_hora := 8;
  end if;

  select exists (
           select 1
             from jsonb_array_elements(
                    coalesce(v_horarios -> 'valle', '[]'::jsonb)
                  ) as elem
            where (elem ->> 'dia')::int  = p_dia
              and (elem ->> 'hora')::int = v_hora
         )
    into v_es_valle;

  if v_es_valle then
    return json_build_object('creditos', v_min, 'tipo', 'valle', 'ok', true);
  end if;

  -- Todo lo no marcado es pico. Ya no existe el promedio.
  return json_build_object('creditos', v_max, 'tipo', 'pico', 'ok', true);
end;
$function$;

-- ----------------------------------------------------------------------------
-- 5 · Los dos triggers de precio pasan la categoría resuelta en vez de null.
--
--     ⚠️ Orden de triggers, medido: los BEFORE corren por orden alfabético y
--     `..._fija_precio` corre ANTES que `..._sync_categorias_*`. Un cliente
--     viejo que mande sólo `categoria` (escalar) llega acá con el array vacío
--     ⇒ se usa coalesce(array no vacío, array[categoria]).
--
--     Se suma `categorias` a la lista de "qué cambió" del UPDATE: cambiar la
--     categoría (Sauna → Yoga) ahora ES un cambio de precio y tiene que
--     recalcular. Antes no lo era porque la categoría no afectaba el precio.
-- ----------------------------------------------------------------------------
create or replace function public.clases_fija_precio()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
declare
  v_res  json;
  v_serv record;
  v_cats text[];
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  -- Workshops: el precio se carga en pesos y lo deriva Aura. No se toca.
  if coalesce(new.tipo, 'clase') = 'workshop' then
    return new;
  end if;

  -- En un UPDATE solo actuamos si cambió algo que afecta el precio. Sin esto
  -- recalcularíamos en cada reserva (que toca lugares_disponibles) al pedo.
  -- `tipo` cierra el bypass workshop -> clase; `categorias` entra desde el
  -- 27/8 porque un servicio de precio fijo hace que la categoría SEA precio.
  if tg_op = 'UPDATE'
     and new.creditos   is not distinct from old.creditos
     and new.fecha      is not distinct from old.fecha
     and new.estudio_id is not distinct from old.estudio_id
     and new.tipo       is not distinct from old.tipo
     and new.categorias is not distinct from old.categorias then
    return new;
  end if;

  -- El array puede venir vacío con el escalar cargado (cliente viejo, y este
  -- trigger corre antes que el sync). Resuelto acá, no en el sync.
  v_cats := coalesce(nullif(new.categorias, '{}'::text[]),
                     case when nullif(trim(coalesce(new.categoria,'')),'') is not null
                          then array[trim(new.categoria)] end);

  -- Servicio de precio fijo: si UNA de las categorías lo tiene, ese es el
  -- precio. Si DOS lo tienen, servicio_precio_fijo() levanta excepción y el
  -- guardado se rechaza entero (decisión 2).
  select * into v_serv from public.servicio_precio_fijo(new.estudio_id, v_cats);

  v_res := public.calcular_precio_clase(
    new.estudio_id,
    v_serv.servicio,
    extract(isodow from new.fecha)::int,
    to_char(new.fecha, 'HH24:MI')
  );

  -- Estudio sin precio configurado: se rechaza. Antes se dejaba pasar y la
  -- clase se quedaba con el default escondido de 10 creditos.
  if not coalesce((v_res ->> 'ok')::boolean, false) then
    raise exception 'Falta configurar el precio de este estudio para poder cargar clases. Escribinos y lo activamos.';
  end if;

  new.creditos    := (v_res ->> 'creditos')::int;
  new.tipo_precio := v_res ->> 'tipo';

  return new;
end;
$function$;

create or replace function public.horarios_fijos_fija_precio()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
declare
  v_res  json;
  v_serv record;
  v_cats text[];
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  -- to_jsonb en vez de new.tipo: horarios_fijos puede no tener esa columna en
  -- todos los entornos y así el trigger no rompe si falta.
  if coalesce(to_jsonb(new) ->> 'tipo', 'clase') = 'workshop' then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and new.creditos    is not distinct from old.creditos
     and new.dia_semana  is not distinct from old.dia_semana
     and new.hora_inicio is not distinct from old.hora_inicio
     and new.estudio_id  is not distinct from old.estudio_id
     and new.categorias  is not distinct from old.categorias then
    return new;
  end if;

  v_cats := coalesce(nullif(new.categorias, '{}'::text[]),
                     case when nullif(trim(coalesce(new.categoria,'')),'') is not null
                          then array[trim(new.categoria)] end);

  select * into v_serv from public.servicio_precio_fijo(new.estudio_id, v_cats);

  v_res := public.calcular_precio_clase(
    new.estudio_id,
    v_serv.servicio,
    new.dia_semana,
    to_char(new.hora_inicio, 'HH24:MI')
  );

  -- Mismo criterio que en clases: sin precio configurado no se carga grilla.
  if not coalesce((v_res ->> 'ok')::boolean, false) then
    raise exception 'Falta configurar el precio de este estudio para poder cargar clases. Escribinos y lo activamos.';
  end if;

  new.creditos := (v_res ->> 'creditos')::int;

  return new;
end;
$function$;

-- ----------------------------------------------------------------------------
-- 6 · El generador nocturno: la ETIQUETA ya no puede pisar 'servicio'.
--     El precio ya lo respetaba (usa v_h.creditos si está); lo que recalculaba
--     siempre era tipo_precio, y un sauna salía marcado 'valle' o 'pico'.
--     Ahora resuelve el servicio del horario y se lo pasa al cálculo: si es
--     servicio, etiqueta 'servicio'; si no, la franja como siempre.
-- ----------------------------------------------------------------------------
create or replace function public.generar_clases_estudio(p_estudio_id integer, p_weeks integer default 9)
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_now          timestamp := (now() at time zone 'America/Argentina/Buenos_Aires');
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
  v_ocupadas     int := 0;
  v_resultado    json;
  v_creditos     int;
  v_tipo         text;
  v_serv         record;
begin
  -- [FIX seguridad] Un usuario solo genera la grilla de un estudio que administra
  -- (o superadmin). El cron corre como service_role (auth.uid() null) y salta.
  if auth.uid() is not null and not public.es_miembro_de_estudio(p_estudio_id::bigint) then
    return json_build_object('creadas', 0, 'omitidas', 0, 'error', 'no_autorizado');
  end if;

  v_week_start := v_now::date - ((extract(isodow from v_now)::int) - 1);

  for v_h in
    select * from public.horarios_fijos
     where estudio_id = p_estudio_id and coalesce(activo, true) = true
  loop
    if v_h.dia_semana is null or v_h.dia_semana < 1 or v_h.dia_semana > 7 then
      v_omitidas := v_omitidas + 1; continue;
    end if;
    if v_h.nombre is null or trim(v_h.nombre) = '' then
      v_omitidas := v_omitidas + 1; continue;
    end if;

    v_hora   := coalesce(extract(hour from v_h.hora_inicio)::int, 8);
    v_minuto := coalesce(extract(minute from v_h.hora_inicio)::int, 0);
    v_hora_text := lpad(v_hora::text, 2, '0') || ':' || lpad(v_minuto::text, 2, '0');

    -- Servicio de precio fijo del horario (2026-08-27). Si el horario quedó
    -- guardado con dos servicios (no debería: el trigger lo rechaza), el
    -- helper levantaría; se protege para que UNA grilla rota no frene la
    -- generación de todo el estudio.
    begin
      select * into v_serv
        from public.servicio_precio_fijo(p_estudio_id::bigint, v_h.categorias);
    exception when others then
      v_serv := null;
    end;

    -- La ETIQUETA sale SIEMPRE de la regla, aunque el precio venga del horario
    -- fijo. `horarios_fijos` no tiene columna `tipo_precio`, así que no hay de
    -- dónde copiarla: hay que calcularla. Con servicio, 'servicio'.
    v_resultado := public.calcular_precio_clase(p_estudio_id, v_serv.servicio, v_h.dia_semana, v_hora_text);
    v_tipo := coalesce(v_resultado->>'tipo', 'normal');

    if coalesce(v_h.creditos, 0) > 0 then
      -- El PRECIO sigue saliendo del horario fijo (D3): si el estudio tiene uno
      -- cargado, la grilla lo respeta en vez de recalcularlo.
      v_creditos := v_h.creditos;
    elsif (v_resultado->>'creditos') is not null then
      v_creditos := (v_resultado->>'creditos')::int;
    else
      v_creditos := 0;
    end if;

    -- Servicio con precio 0 (clase gratis): v_h.creditos puede ser 0 y el
    -- cálculo también ⇒ v_creditos 0 es válido acá, el CHECK de clases lo
    -- permite (creditos >= 0).

    for v_week_offset in 0..(p_weeks - 1) loop
      v_fecha := (v_week_start + (v_week_offset * 7 + (v_h.dia_semana - 1)))::timestamp
                 + make_interval(hours => v_hora, mins => v_minuto);

      select id into v_existente_id
        from public.clases
       where estudio_id = p_estudio_id and horario_fijo_id = v_h.id
         and fecha between v_fecha - interval '1 hour' and v_fecha + interval '1 hour'
       limit 1;

      if v_existente_id is not null then
        v_omitidas := v_omitidas + 1; continue;
      end if;

      -- 2026-08-25: SEGUNDO chequeo, por (estudio, fecha exacta), venga de la
      -- grilla que venga o de ninguna. El primero va por horario_fijo_id y
      -- es ciego a las clases HUERFANAS: clases.horario_fijo_id es ON DELETE
      -- SET NULL, asi que borrar una grilla no borra sus clases; si despues
      -- se recrea la grilla, el generador creaba otra clase encima de cada
      -- huerfana (medido: 3 fechas duplicadas). El camino real del Dart
      -- (_deleteFixed) intenta borrar las clases antes, pero cada paso esta
      -- en try/catch: si el candado de borrado (reserva presente/completada)
      -- o cualquier otro error lo frena, la clase queda huerfana y publicada.
      -- Regla: el generador NUNCA crea encima de una clase que ya existe en
      -- ese minuto para ese estudio. Cuenta aparte como 'ocupadas'.
      select id into v_existente_id
        from public.clases
       where estudio_id = p_estudio_id
         and fecha = v_fecha
         -- 2026-08-25: misma clave que el guard de grillas: la sala distingue.
         and lower(trim(coalesce(sala, ''))) = lower(trim(coalesce(v_h.sala, '')))
       limit 1;

      if v_existente_id is not null then
        v_ocupadas := v_ocupadas + 1; continue;
      end if;

      -- 2026-08-25: no publicar lo que ya paso. La semana arranca el lunes,
      -- asi que una grilla creada un martes publicaba el lunes anterior
      -- (medido: 3 clases del 24/8 al crear el 25/8). Se cuenta como omitida.
      if v_fecha < v_now then
        v_omitidas := v_omitidas + 1; continue;
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
        v_creditos, v_h.reserva_cierre_minutos, v_h.cancelacion_cierre_minutos,
        coalesce(v_h.categorias, '{}'), v_h.sala, v_tipo
      );
      v_creadas := v_creadas + 1;
    end loop;
  end loop;

  return json_build_object('creadas', v_creadas, 'omitidas', v_omitidas, 'ocupadas', v_ocupadas);
end;
$function$;

-- ----------------------------------------------------------------------------
-- 7 · El recalculador masivo también resuelve el servicio por fila.
--     Era el más peligroso: corre cada vez que se guardan precios en el
--     backoffice y pisaba clases Y horarios con la franja. Ahora, una clase
--     cuya categoría tiene precio fijo conserva su precio de servicio.
-- ----------------------------------------------------------------------------
create or replace function public.admin_recalcular_precios_estudio(
  p_estudio_id bigint, p_incluir_pasadas boolean default true
) returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_clase  record;
  v_res    json;
  v_serv   record;
  v_count  int := 0;
  v_desde  timestamp;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  v_desde := case
    when p_incluir_pasadas then '-infinity'::timestamp
    else (timezone('America/Argentina/Buenos_Aires', now()))::date::timestamp
  end;

  for v_clase in
    select id, estudio_id, fecha, categorias
      from public.clases
     where estudio_id = p_estudio_id
       and coalesce(tipo, 'clase') <> 'workshop'
       and (fecha)::timestamp >= v_desde
  loop
    -- Una fila con dos servicios (no debería existir) no frena el resto.
    begin
      select * into v_serv
        from public.servicio_precio_fijo(v_clase.estudio_id, v_clase.categorias);
    exception when others then
      v_serv := null;
    end;

    v_res := public.calcular_precio_clase(
      v_clase.estudio_id, v_serv.servicio,
      extract(isodow from v_clase.fecha)::int,
      to_char(v_clase.fecha, 'HH24:MI')
    );
    if coalesce((v_res ->> 'ok')::boolean, false) then
      update public.clases
         set creditos    = (v_res ->> 'creditos')::int,
             tipo_precio = v_res ->> 'tipo'
       where id = v_clase.id;
      v_count := v_count + 1;
    end if;
  end loop;

  -- Los horarios fijos también, para que las próximas generaciones arranquen
  -- con el precio correcto. Mismo criterio: el servicio de SU array.
  update public.horarios_fijos h
     set creditos = (calc.res ->> 'creditos')::int
    from (
      select hf.id,
             public.calcular_precio_clase(
               hf.estudio_id,
               (select s.servicio from public.servicio_precio_fijo(hf.estudio_id, hf.categorias) s limit 1),
               hf.dia_semana, to_char(hf.hora_inicio, 'HH24:MI')
             ) as res
        from public.horarios_fijos hf
       where hf.estudio_id = p_estudio_id
    ) calc
   where h.id = calc.id
     and coalesce(to_jsonb(h) ->> 'tipo', 'clase') <> 'workshop'
     and coalesce((calc.res ->> 'ok')::boolean, false);

  return v_count;
end;
$function$;

-- ----------------------------------------------------------------------------
-- 8 · Decisión 9: cada estudio ve las genéricas + SOLO sus servicios.
--     Firma intacta ⇒ la app YA instalada recibe la lista filtrada sola.
--     El backoffice (is_admin) sigue viéndolas todas para poder asignarlas.
--     "Es servicio" = tiene precio fijo activo para ALGÚN estudio.
-- ----------------------------------------------------------------------------
create or replace function public.admin_list_studio_categories()
returns table (id bigint, nombre text, activa boolean, en_uso bigint)
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
begin
  -- 2026-08-24: guard mínimo — sólo corta anon. La lista es pública de todos
  -- modos (study_categories tiene RLS SELECT using true).
  if auth.uid() is null then
    raise exception 'No autorizado';
  end if;

  return query
  select
    sc.id::bigint,
    sc.nombre::text,
    sc.activa::boolean,
    (select count(*)::bigint
       from public.estudios e
      where sc.nombre = any(e.categorias)) as en_uso
  from public.study_categories sc
  where
    -- Superadmin: todas, siempre (el backoffice las asigna).
    public.is_admin()
    -- Genérica: no es servicio de precio fijo de nadie.
    or not exists (
         select 1 from public.estudio_servicios_precio esp
          where esp.servicio = sc.nombre and esp.activo
       )
    -- Servicio propio: configurado para un estudio que el caller administra.
    or exists (
         select 1
           from public.estudio_servicios_precio esp
           join public.estudio_admins ea on ea.estudio_id = esp.estudio_id
          where esp.servicio = sc.nombre
            and esp.activo
            and ea.usuario_id = auth.uid()
       )
  order by sc.activa desc, sc.nombre;
end;
$function$;

-- ----------------------------------------------------------------------------
-- 9 · La RPC del backoffice para configurar un servicio.
--     Aplica la decisión 3 al cambiar un precio: recalcula SOLO las clases
--     futuras SIN reserva viva; las que ya tienen reserva no se tocan (la
--     liquidación y las devoluciones usan el snapshot creditos_usados, así
--     que el precio viejo de esas queda coherente con lo que se cobró).
-- ----------------------------------------------------------------------------
create or replace function public.admin_set_servicio_precio(
  p_estudio_id bigint,
  p_servicio   text,
  p_creditos   integer,
  p_activo     boolean default true
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_recalculadas int := 0;
  v_horarios     int := 0;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  if p_creditos is null or p_creditos < 0 or p_creditos > 500 then
    raise exception 'Créditos inválidos (0 a 500)';
  end if;
  if not exists (select 1 from public.estudios e where e.id = p_estudio_id) then
    raise exception 'El estudio no existe';
  end if;
  -- El nombre tiene que existir en el catálogo global: es lo que el estudio
  -- elige en el multi-select. Si no está, primero se crea la categoría.
  if not exists (
    select 1 from public.study_categories sc
     where sc.nombre = p_servicio and sc.activa
  ) then
    raise exception 'La categoría "%" no existe (o está inactiva) en el catálogo. Creala primero en Configuración.', p_servicio;
  end if;

  insert into public.estudio_servicios_precio (estudio_id, servicio, creditos, activo)
  values (p_estudio_id, p_servicio, p_creditos, coalesce(p_activo, true))
  on conflict (estudio_id, servicio)
    do update set creditos = excluded.creditos, activo = excluded.activo;

  -- Decisión 3: futuras sin reserva viva. La huella de "reserva viva" es la
  -- misma que usa el resto del sistema: todo lo que no está cancelado.
  update public.clases c
     set creditos    = case when p_activo then p_creditos else c.creditos end,
         tipo_precio = case when p_activo then 'servicio' else c.tipo_precio end
   where c.estudio_id = p_estudio_id
     and coalesce(c.tipo, 'clase') <> 'workshop'
     and p_servicio = any (c.categorias)
     and c.fecha >= (now() at time zone 'America/Argentina/Buenos_Aires')
     and not exists (
           select 1 from public.reservas r
            where r.clase_id = c.id
              and coalesce(r.estado,'') not in ('cancelada','cancelada_por_estudio')
         );
  get diagnostics v_recalculadas = row_count;

  -- Y los horarios fijos con ese servicio, para que la próxima generación
  -- nazca con el precio nuevo.
  update public.horarios_fijos hf
     set creditos = p_creditos
   where hf.estudio_id = p_estudio_id
     and p_servicio = any (hf.categorias)
     and p_activo;
  get diagnostics v_horarios = row_count;

  return jsonb_build_object(
    'ok', true,
    'clases_recalculadas', v_recalculadas,
    'horarios_actualizados', v_horarios
  );
end;
$function$;

revoke execute on function public.admin_set_servicio_precio(bigint, text, integer, boolean) from public, anon;
grant  execute on function public.admin_set_servicio_precio(bigint, text, integer, boolean) to authenticated, service_role;

notify pgrst, 'reload schema';
