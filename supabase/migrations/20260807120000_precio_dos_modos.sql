-- ============================================================================
-- AURA — Precio por clase: DOS MODOS por estudio (2026-08-07)
-- ============================================================================
--
-- Reemplaza el modelo anterior (el estudio tipeaba los créditos y el cliente
-- "sugería" un rango) por un precio que define Aura desde el backoffice y que
-- la BASE fija sola al insertar/actualizar la clase.
--
--   estudios.tipo_precio = 'fijo'   -> todas las clases valen creditos_min.
--   estudios.tipo_precio = 'rango'  -> el precio sale del horario:
--        franja marcada pico   -> creditos_max
--        franja marcada valle  -> creditos_min
--        sin marcar (normal)   -> round((min + max) / 2)
--
-- La grilla pico/valle vive en estudios.horarios_config:
--   {"pico": [{"dia": 1, "rango": "tarde_noche"}], "valle": [...]}
--   dia = isodow (1 = lunes ... 7 = domingo)
--   rango = madrugada 0-6, manana_temprano 6-9, manana 9-12, mediodia 12-15,
--           tarde 15-18, tarde_noche 18-21, noche 21-24
--
-- FUENTE DE VERDAD: estudios.tipo_precio / creditos_min / creditos_max /
-- horarios_config. `precio_config` (jsonb) queda DEPRECADO: solo se lee como
-- fallback para estudios que todavía no tengan las columnas cargadas.
--
-- Ojo con los nombres: estudios.tipo_precio es el MODO ('fijo'|'rango'),
-- clases.tipo_precio es el RESULTADO ('pico'|'valle'|'normal'|'experiencia').
-- ============================================================================


-- ── 1. COLUMNAS (idempotente) ───────────────────────────────────────────────

alter table public.estudios
  add column if not exists tipo_precio text not null default 'fijo',
  add column if not exists creditos_min integer,
  add column if not exists creditos_max integer,
  add column if not exists horarios_config jsonb not null
    default '{"pico":[],"valle":[]}'::jsonb;

-- El default pasa de 'rango' a 'fijo': un estudio nuevo arranca con precio
-- único hasta que Aura decida lo contrario.
alter table public.estudios alter column tipo_precio set default 'fijo';

do $$
begin
  alter table public.estudios drop constraint if exists estudios_tipo_precio_check;
  alter table public.estudios
    add constraint estudios_tipo_precio_check check (tipo_precio in ('fijo', 'rango'));
end $$;


-- ── 2. BACKFILL: todos los estudios actuales pasan a modo 'fijo' ────────────
--
-- "Su precio actual" se resuelve en este orden:
--   1) creditos_min ya cargado desde el backoffice
--   2) precio_config->>'min' (config vieja de pico/valle)
--   3) el precio más repetido entre sus clases no-workshop
--   4) 10 (último recurso)
--
-- No pisa lo que ya esté bien cargado: solo completa lo que está en null.
--
-- Corre UNA SOLA VEZ. Queda marcado en configuracion_global para que volver a
-- ejecutar este archivo no te devuelva a 'fijo' los estudios que después
-- pasaste a 'rango' a mano.

do $$
begin
  if exists (
    select 1 from public.configuracion_global
     where clave = 'precio_dos_modos_backfill'
  ) then
    raise notice 'Backfill de precio ya aplicado antes: se saltea.';
    return;
  end if;

  with moda_clases as (
    select estudio_id, creditos,
           row_number() over (
             partition by estudio_id
             order by count(*) desc, creditos desc
           ) as rn
      from public.clases
     where coalesce(tipo, 'clase') <> 'workshop'
       and coalesce(creditos, 0) > 0
     group by estudio_id, creditos
  )
  update public.estudios e
     set tipo_precio  = 'fijo',
         creditos_min = coalesce(
           e.creditos_min,
           -- ::numeric primero: precio_config puede traer 10.0 y ::int directo
           -- sobre '10.0' revienta.
           (nullif(e.precio_config ->> 'min', '')::numeric)::int,
           (select m.creditos from moda_clases m
             where m.estudio_id = e.id and m.rn = 1),
           10
         )
   where true;

  -- El techo solo se completa si falta o si quedó por debajo del piso. NO se
  -- aplasta un máximo ya negociado: Sculpt tenía 14/16 cargado y pasarlo a
  -- modo fijo no tiene por qué hacerte perder el 16. En modo fijo el máximo se
  -- ignora (calcular_precio_clase usa solo creditos_min), así que guardarlo es
  -- inofensivo y te lo deja listo para cuando lo pases a rango.
  update public.estudios
     set creditos_max = creditos_min
   where creditos_max is null
      or creditos_max < creditos_min;

  insert into public.configuracion_global (clave, valor)
  values ('precio_dos_modos_backfill', 'done')
  on conflict (clave) do nothing;
end $$;


-- ── 3. calcular_precio_clase v4 (dos modos) ─────────────────────────────────
--
-- Misma firma que la v3: generar_clases_estudio (D3) la llama con 4 args.
-- `p_categoria` se ignora (el precio es por estudio), se mantiene por compat.
--
-- Devuelve {creditos, tipo, ok}. ok=false significa "estudio sin precio
-- configurado": los llamadores NO deben pisar el precio en ese caso.
--
-- p_estudio_id es BIGINT, no INT: clases.estudio_id es bigint y bigint->int no
-- es un cast implícito en Postgres, así que la versión vieja (int) fallaba con
-- "function does not exist" al llamarla desde un trigger o una query suelta.
-- Al revés sí funciona (int->bigint ensancha solo), así que generar_clases_estudio
-- y los demás llamadores que pasan int siguen resolviendo bien.

-- Limpiamos todas las firmas viejas antes de crear la nueva, para no quedar con
-- dos versiones conviviendo. Las llamadas función-a-función no son dependencias
-- registradas en PG, así que este drop no rompe generar_clases_estudio.
do $$
declare
  v_fn record;
begin
  for v_fn in
    select p.oid::regprocedure as firma
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = 'calcular_precio_clase'
  loop
    execute format('drop function if exists %s', v_fn.firma);
  end loop;
end $$;

create function public.calcular_precio_clase(
  p_estudio_id bigint,
  p_categoria  text,
  p_dia        int,
  p_hora       text
) returns json
language plpgsql
stable
-- SECURITY DEFINER a propósito: el trigger la llama con el rol del cliente y
-- necesita leer la config del estudio sí o sí. Si la RLS de `estudios` tapara
-- la fila, devolvería ok=false y el precio del cliente pasaría sin corregir,
-- que es justo el agujero que estamos cerrando. Solo expone el precio, que el
-- estudio ya ve en su propio panel.
security definer
set search_path = public
as $$
declare
  v_tipo_estudio text;
  v_modo         text;
  v_min          int;
  v_max          int;
  v_config       jsonb;
  v_horarios     jsonb;
  v_hh           int;
  v_rango        text;
  v_elem         jsonb;
  v_es_pico      boolean := false;
  v_es_valle     boolean := false;
begin
  select coalesce(e.tipo_estudio, 'fitness'),
         coalesce(e.tipo_precio, 'fijo'),
         e.creditos_min, e.creditos_max, e.precio_config, e.horarios_config
    into v_tipo_estudio, v_modo, v_min, v_max, v_config, v_horarios
    from public.estudios e
   where e.id = p_estudio_id;

  if not found then
    return json_build_object('creditos', null, 'tipo', 'normal', 'ok', false);
  end if;

  -- Fallback a la config vieja para estudios sin las columnas nuevas.
  -- ::numeric primero porque precio_config puede traer 10.0.
  v_min := coalesce(v_min, (nullif(v_config ->> 'min', '')::numeric)::int);
  v_max := coalesce(v_max, (nullif(v_config ->> 'max', '')::numeric)::int, v_min);

  if v_min is null then
    return json_build_object('creditos', null, 'tipo', 'normal', 'ok', false);
  end if;
  if v_max is null or v_max < v_min then
    v_max := v_min;
  end if;

  -- Estudios de experiencias: precio fijo, los workshops van por otro circuito.
  if v_tipo_estudio = 'experiencia' then
    return json_build_object('creditos', v_min, 'tipo', 'experiencia', 'ok', true);
  end if;

  -- MODO FIJO: un único precio, sin importar el horario.
  if v_modo <> 'rango' then
    return json_build_object('creditos', v_min, 'tipo', 'normal', 'ok', true);
  end if;

  -- MODO RANGO: el precio sale de la franja horaria.
  v_hh := coalesce(nullif(split_part(coalesce(p_hora, '08:00'), ':', 1), '')::int, 8);
  v_rango := case
    when v_hh < 6  then 'madrugada'
    when v_hh < 9  then 'manana_temprano'
    when v_hh < 12 then 'manana'
    when v_hh < 15 then 'mediodia'
    when v_hh < 18 then 'tarde'
    when v_hh < 21 then 'tarde_noche'
    else                'noche'
  end;

  for v_elem in
    select * from jsonb_array_elements(coalesce(v_horarios -> 'pico', '[]'::jsonb))
  loop
    if (v_elem ->> 'dia')::int = p_dia and (v_elem ->> 'rango') = v_rango then
      v_es_pico := true;
      exit;
    end if;
  end loop;

  if not v_es_pico then
    for v_elem in
      select * from jsonb_array_elements(coalesce(v_horarios -> 'valle', '[]'::jsonb))
    loop
      if (v_elem ->> 'dia')::int = p_dia and (v_elem ->> 'rango') = v_rango then
        v_es_valle := true;
        exit;
      end if;
    end loop;
  end if;

  if v_es_pico then
    return json_build_object('creditos', v_max, 'tipo', 'pico', 'ok', true);
  elsif v_es_valle then
    return json_build_object('creditos', v_min, 'tipo', 'valle', 'ok', true);
  end if;

  -- Sin marcar (y también el caso "modo rango sin grilla cargada todavía"):
  -- promedio entre mínimo y máximo.
  return json_build_object(
    'creditos', round((v_min + v_max) / 2.0)::int,
    'tipo', 'normal',
    'ok', true
  );
end;
$$;

grant execute on function public.calcular_precio_clase(bigint, text, int, text)
  to authenticated, service_role;


-- ── 4. BLINDAJE: la base fija el precio al escribir la clase ────────────────
--
-- Sobrescribe en vez de rechazar: si una app vieja manda 20, se guarda el
-- precio correcto igual y el estudio no ve un error. El filtro por
-- current_user deja pasar los RPC/crons (postgres, service_role), que ya
-- calculan bien por su cuenta. Mismo patrón que clases_gate_profe (D-profe).

create or replace function public.clases_fija_precio()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_res json;
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
  if tg_op = 'UPDATE'
     and new.creditos   is not distinct from old.creditos
     and new.fecha      is not distinct from old.fecha
     and new.estudio_id is not distinct from old.estudio_id then
    return new;
  end if;

  v_res := public.calcular_precio_clase(
    new.estudio_id,
    null,
    extract(isodow from new.fecha)::int,
    to_char(new.fecha, 'HH24:MI')
  );

  -- Estudio sin precio configurado: no pisamos nada (no bloqueamos la carga).
  if coalesce((v_res ->> 'ok')::boolean, false) then
    new.creditos    := (v_res ->> 'creditos')::int;
    new.tipo_precio := v_res ->> 'tipo';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_clases_fija_precio on public.clases;
create trigger trg_clases_fija_precio
  before insert or update on public.clases
  for each row execute function public.clases_fija_precio();


-- Mismo blindaje en horarios_fijos: si no, el estudio mete el precio por la
-- grilla semanal y generar_clases_estudio lo propaga a 3 meses de clases.
create or replace function public.horarios_fijos_fija_precio()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_res json;
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
     and new.estudio_id  is not distinct from old.estudio_id then
    return new;
  end if;

  v_res := public.calcular_precio_clase(
    new.estudio_id,
    null,
    new.dia_semana,
    to_char(new.hora_inicio, 'HH24:MI')
  );

  if coalesce((v_res ->> 'ok')::boolean, false) then
    new.creditos := (v_res ->> 'creditos')::int;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_horarios_fijos_fija_precio on public.horarios_fijos;
create trigger trg_horarios_fijos_fija_precio
  before insert or update on public.horarios_fijos
  for each row execute function public.horarios_fijos_fija_precio();


-- ── 5. El estudio tampoco puede tocar la grilla pico/valle ──────────────────
-- Suma horarios_config y precio_config a las columnas que solo define Aura.
-- (El resto del cuerpo es igual al de 20260722140000.)

create or replace function public.estudios_bloquear_columnas_aura()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if new.comision_aura is distinct from old.comision_aura
     or new.comision_workshop is distinct from old.comision_workshop
     or new.valor_credito is distinct from old.valor_credito
     or new.creditos_min is distinct from old.creditos_min
     or new.creditos_max is distinct from old.creditos_max
     or new.tipo_precio is distinct from old.tipo_precio
     or new.horarios_config is distinct from old.horarios_config
     or new.precio_config is distinct from old.precio_config
     or new.fecha_inicio_cobro is distinct from old.fecha_inicio_cobro then
    raise exception 'Comisiones y precios los define Aura desde el backoffice';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_estudios_columnas_aura on public.estudios;
create trigger trg_estudios_columnas_aura
  before update on public.estudios
  for each row execute function public.estudios_bloquear_columnas_aura();


-- ── 6. RPC del backoffice para guardar modo + precios + grilla ──────────────
-- Necesario porque el trigger de arriba bloquea el UPDATE directo desde el
-- cliente (el backoffice también corre como `authenticated`).

-- p_estudio_id bigint por el mismo motivo que calcular_precio_clase: los id de
-- estudios/clases son bigint y bigint->int no castea solo.
create or replace function public.admin_set_pricing_estudio(
  p_estudio_id      bigint,
  p_tipo_precio     text,
  p_creditos_min    int,
  p_creditos_max    int default null,
  p_horarios_config jsonb default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_modo text;
  v_min  int := p_creditos_min;
  v_max  int := p_creditos_max;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  v_modo := coalesce(nullif(trim(p_tipo_precio), ''), 'fijo');
  if v_modo not in ('fijo', 'rango') then
    raise exception 'Modo de precio invalido: %', v_modo;
  end if;

  if v_min is null or v_min <= 0 then
    raise exception 'El precio en creditos tiene que ser mayor a 0';
  end if;

  if v_modo = 'fijo' then
    v_max := v_min;
  else
    if v_max is null or v_max < v_min then
      raise exception 'El maximo no puede ser menor al minimo';
    end if;
  end if;

  update public.estudios
     set tipo_precio     = v_modo,
         creditos_min    = v_min,
         creditos_max    = v_max,
         horarios_config = case
           when v_modo = 'fijo' then '{"pico":[],"valle":[]}'::jsonb
           else coalesce(p_horarios_config, horarios_config,
                         '{"pico":[],"valle":[]}'::jsonb)
         end
   where id = p_estudio_id;
end;
$$;

revoke execute on function
  public.admin_set_pricing_estudio(bigint, text, int, int, jsonb) from public, anon;
grant execute on function
  public.admin_set_pricing_estudio(bigint, text, int, int, jsonb)
  to authenticated, service_role;


-- ── 7. Recálculo de clases y horarios ya cargados ───────────────────────────
--
-- p_incluir_pasadas = true reescribe también las clases que ya pasaron, para
-- que no queden precios viejos mezclados. Ojo: NO afecta la plata. Las
-- liquidaciones y el consumo de créditos salen de reservas.creditos_usados
-- (snapshot al momento de reservar), no de clases.creditos. Lo único que
-- cambia es el número que se ve en el historial de una clase pasada.

create or replace function public.admin_recalcular_precios_estudio(
  p_estudio_id      bigint,
  p_incluir_pasadas boolean default true
) returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_clase  record;
  v_res    json;
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
    select id, estudio_id, fecha
      from public.clases
     where estudio_id = p_estudio_id
       and coalesce(tipo, 'clase') <> 'workshop'
       and (fecha)::timestamp >= v_desde
  loop
    v_res := public.calcular_precio_clase(
      v_clase.estudio_id, null,
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
  -- con el precio correcto.
  update public.horarios_fijos h
     set creditos = (calc.res ->> 'creditos')::int
    from (
      select id,
             public.calcular_precio_clase(
               estudio_id, null, dia_semana, to_char(hora_inicio, 'HH24:MI')
             ) as res
        from public.horarios_fijos
       where estudio_id = p_estudio_id
    ) calc
   where h.id = calc.id
     and coalesce(to_jsonb(h) ->> 'tipo', 'clase') <> 'workshop'
     and coalesce((calc.res ->> 'ok')::boolean, false);

  return v_count;
end;
$$;

revoke execute on function
  public.admin_recalcular_precios_estudio(bigint, boolean) from public, anon;
grant execute on function
  public.admin_recalcular_precios_estudio(bigint, boolean)
  to authenticated, service_role;


-- aplicar_pricing_a_clases_futuras se mantiene por compat (la llama la
-- pantalla de pricing vieja), ahora delegando en la función de arriba.
create or replace function public.aplicar_pricing_a_clases_futuras(
  p_estudio_id int
) returns int
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.admin_recalcular_precios_estudio(p_estudio_id, false);
end;
$$;

grant execute on function public.aplicar_pricing_a_clases_futuras(int)
  to authenticated, service_role;


-- ── 8. RECÁLCULO GLOBAL de todo lo ya cargado ──────────────────────────────
-- Corre como dueño de la migración (no como `authenticated`), así que los
-- triggers de arriba no interfieren: el UPDATE escribe el valor calculado.

update public.clases c
   set creditos    = (calc.res ->> 'creditos')::int,
       tipo_precio = calc.res ->> 'tipo'
  from (
    select id,
           public.calcular_precio_clase(
             estudio_id, null,
             extract(isodow from fecha)::int,
             to_char(fecha, 'HH24:MI')
           ) as res
      from public.clases
     where coalesce(tipo, 'clase') <> 'workshop'
  ) calc
 where c.id = calc.id
   and coalesce((calc.res ->> 'ok')::boolean, false);

update public.horarios_fijos h
   set creditos = (calc.res ->> 'creditos')::int
  from (
    select id,
           public.calcular_precio_clase(
             estudio_id, null, dia_semana, to_char(hora_inicio, 'HH24:MI')
           ) as res
      from public.horarios_fijos
  ) calc
 where h.id = calc.id
   and coalesce(to_jsonb(h) ->> 'tipo', 'clase') <> 'workshop'
   and coalesce((calc.res ->> 'ok')::boolean, false);
