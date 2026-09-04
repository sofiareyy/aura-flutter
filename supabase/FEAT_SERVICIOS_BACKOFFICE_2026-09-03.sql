-- ============================================================================
-- SERVICIOS DE PRECIO FIJO — la parte de BASE que necesita la pantalla del
-- backoffice (3/9/2026). Tres piezas chicas, todas aditivas.
--
--   1. `admin_set_servicio_precio` gana `p_solo_preview`: devuelve los conteos
--      sin escribir. El PREDICADO de "qué clases cambian" vive UNA sola vez
--      (se resuelve a un array de ids y después se actualiza por id), así el
--      número que ve Sofía en la confirmación y el que aplica la RPC no se
--      pueden separar nunca.
--   2. Policy de lectura para superadmin en `estudio_servicios_precio`: hoy
--      sólo la leen los miembros del estudio, y el backoffice no podría listar
--      lo que ya cargó.
--   3. La categoría "Running" (creada el 22/8, sin uso en ningún lado) pasa a
--      llamarse "Running club". Es la categoría global del running gratis: se
--      configura a 0 créditos POR ESTUDIO como servicio de precio fijo.
--
-- LA REGLA DE PLATA, que esta función respeta y la pantalla hereda:
--   · clases PASADAS: nunca se tocan (fecha < ahora ART);
--   · clases FUTURAS con una reserva VIVA: quedan selladas al precio con el
--     que se cobró (la reserva ya descontó creditos_usados y esa columna está
--     bloqueada al cliente);
--   · sólo las FUTURAS SIN reserva toman el precio nuevo;
--   · las reservas y las liquidaciones no se tocan JAMÁS: la plata sale de
--     reservas.creditos_usados, no de clases.creditos.
-- Medido en rollback sobre Citra antes de escribir esto (3/9): 0 pasadas
-- tocadas de 199, la futura con reserva conservó su precio, 191/191 futuras
-- sin reserva al precio nuevo, 0 reservas y 0 liquidaciones cambiadas.
-- ============================================================================

-- ── 1 · la RPC con vista previa ─────────────────────────────────────────────
-- Hay que DROPear la firma vieja: CREATE OR REPLACE con un parámetro más crea
-- un OVERLOAD, y PostgREST devuelve 300 (ambiguo) cuando se la llama con los
-- 4 parámetros de siempre.
drop function if exists public.admin_set_servicio_precio(bigint, text, integer, boolean);

create or replace function public.admin_set_servicio_precio(
  p_estudio_id   bigint,
  p_servicio     text,
  p_creditos     integer,
  p_activo       boolean default true,
  p_solo_preview boolean default false
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_ahora_ar        timestamp := (now() at time zone 'America/Argentina/Buenos_Aires');
  v_activo          boolean   := coalesce(p_activo, true);
  v_afectadas       bigint[]  := '{}';   -- futuras SIN reserva viva: las que cambian
  v_selladas        integer   := 0;      -- futuras CON reserva viva: NO cambian
  v_pasadas         integer   := 0;      -- pasadas con la categoría: NO se tocan
  v_horarios        integer   := 0;
  v_precio_anterior integer;
  v_activo_anterior boolean;
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

  select esp.creditos, esp.activo
    into v_precio_anterior, v_activo_anterior
    from public.estudio_servicios_precio esp
   where esp.estudio_id = p_estudio_id and esp.servicio = p_servicio;

  -- ── EL predicado, una sola vez ──────────────────────────────────────────
  -- Futuras, no workshop, con la categoría, y SIN reserva viva. "Viva" es la
  -- misma huella que usa el resto del sistema: todo lo que no está cancelado.
  -- Al DESACTIVAR no se toca ninguna clase (comportamiento de siempre), y el
  -- preview lo dice con un 0 en vez de contar filas que no cambiarían.
  if v_activo then
    select coalesce(array_agg(c.id), '{}')
      into v_afectadas
      from public.clases c
     where c.estudio_id = p_estudio_id
       and coalesce(c.tipo, 'clase') <> 'workshop'
       and p_servicio = any (c.categorias)
       and c.fecha >= v_ahora_ar
       and not exists (
             select 1 from public.reservas r
              where r.clase_id = c.id
                and coalesce(r.estado,'') not in ('cancelada','cancelada_por_estudio')
           );
  end if;

  -- Las que NO cambian, para que la confirmación lo pueda decir con número.
  select count(*) into v_selladas
    from public.clases c
   where c.estudio_id = p_estudio_id
     and coalesce(c.tipo, 'clase') <> 'workshop'
     and p_servicio = any (c.categorias)
     and c.fecha >= v_ahora_ar
     and exists (
           select 1 from public.reservas r
            where r.clase_id = c.id
              and coalesce(r.estado,'') not in ('cancelada','cancelada_por_estudio')
         );

  select count(*) into v_pasadas
    from public.clases c
   where c.estudio_id = p_estudio_id
     and coalesce(c.tipo, 'clase') <> 'workshop'
     and p_servicio = any (c.categorias)
     and c.fecha < v_ahora_ar;

  select count(*) into v_horarios
    from public.horarios_fijos hf
   where hf.estudio_id = p_estudio_id
     and p_servicio = any (hf.categorias);

  if not coalesce(p_solo_preview, false) then
    insert into public.estudio_servicios_precio (estudio_id, servicio, creditos, activo)
    values (p_estudio_id, p_servicio, p_creditos, v_activo)
    on conflict (estudio_id, servicio)
      do update set creditos = excluded.creditos, activo = excluded.activo;

    -- Por id: exactamente las que contó el preview, ni una más.
    if v_activo and coalesce(array_length(v_afectadas, 1), 0) > 0 then
      update public.clases c
         set creditos    = p_creditos,
             tipo_precio = 'servicio'
       where c.id = any (v_afectadas);
    end if;

    -- Y los horarios fijos con ese servicio, para que la próxima generación
    -- nazca con el precio nuevo.
    if v_activo then
      update public.horarios_fijos hf
         set creditos = p_creditos
       where hf.estudio_id = p_estudio_id
         and p_servicio = any (hf.categorias);
    end if;
  end if;

  return jsonb_build_object(
    'ok',                   true,
    'preview',              coalesce(p_solo_preview, false),
    'servicio',             p_servicio,
    'creditos',             p_creditos,
    'activo',               v_activo,
    'precio_anterior',      v_precio_anterior,
    'activo_anterior',      v_activo_anterior,
    'clases_afectadas',     coalesce(array_length(v_afectadas, 1), 0),
    'clases_selladas',      v_selladas,
    'clases_pasadas',       v_pasadas,
    'horarios_actualizados', case when v_activo then v_horarios else 0 end,
    -- nombre viejo, por si algo lo leía
    'clases_recalculadas',  coalesce(array_length(v_afectadas, 1), 0)
  );
end;
$function$;

revoke execute on function public.admin_set_servicio_precio(bigint, text, integer, boolean, boolean) from public, anon;
grant  execute on function public.admin_set_servicio_precio(bigint, text, integer, boolean, boolean) to authenticated, service_role;

-- ── 2 · el backoffice puede LEER lo cargado ─────────────────────────────────
drop policy if exists servicios_precio_select_admin on public.estudio_servicios_precio;
create policy servicios_precio_select_admin
  on public.estudio_servicios_precio
  for select to authenticated
  using (public.is_admin());

-- ── 3 · "Running" → "Running club" ──────────────────────────────────────────
-- La RPC exige is_admin(): desde SQL crudo hay que correrla con las claims del
-- superadmin (ver aura-sql-produccion-management-api). Propaga a estudios,
-- clases y horarios_fijos, aunque hoy nadie la usa (medido: 0 en las 4 tablas).
--   select public.admin_rename_studio_category('Running', 'Running club');

notify pgrst, 'reload schema';

-- ── Verificación ────────────────────────────────────────────────────────────
--   select proname, pg_get_function_arguments(oid) from pg_proc
--    where proname = 'admin_set_servicio_precio';   ⇒ UNA sola fila, 5 params
--   select policyname from pg_policies where tablename='estudio_servicios_precio';
--   select nombre from study_categories where nombre ilike 'running%';
