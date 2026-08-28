-- ============================================================================
-- GRILLAS CON ANOTADAS: BLOQUEAR, NO MOVER (decisión de la usuaria, 28/8)
--
-- Regla: una clase con alumnas anotadas NO se mueve, ni de a una ni en bloque.
-- El estudio cancela esas clases (devuelve créditos + avisa, camino que ya
-- existe y está probado) y recién después reorganiza.
--
-- Cubre los 4 puntos + la colisión:
--   1. Mover una GRILLA con clases anotadas  -> bloqueado, mensaje con detalle
--   2. Mover una CLASE suelta con anotadas   -> bloqueado (hoy no tenía guard)
--   3. Borrar la grilla                       -> cancela con devolución las
--      clases con reservas en vez de dejarlas huérfanas vivas
--   4. Bajar el cupo por debajo de anotadas   -> bloqueado con el número
--   5. Colisión: mover clases (aunque estén vacías) encima de otra clase del
--      estudio en el mismo minuto/sala -> bloqueado. SIGUE siendo posible con
--      el enfoque de bloquear: el guard 1 sólo protege clases CON anotadas;
--      una grilla vacía igual podía caer encima de una clase suelta ocupada
--      (medido el 28/8: "Clase suelta + Grilla A" en el mismo minuto).
--
-- Todos los guards eximen a current_user fuera de authenticated/anon (mismo
-- patrón que el candado de borrado): las RPC security definer, el cron y las
-- correcciones por SQL de Aura pasan.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- A · Guard por CLASE (puntos 2, 4 y 5): BEFORE UPDATE en clases.
--     Corre también durante el movimiento en bloque (el trigger de la grilla
--     hace un UPDATE de clases como el usuario), así que la colisión queda
--     cubierta en un solo lugar para los dos caminos.
-- ----------------------------------------------------------------------------
create or replace function public.clases_guard_cambios_con_anotadas()
returns trigger
language plpgsql
set search_path to 'public'
as $$
declare
  v_anotadas int;
  v_dias constant text[] :=
    array['lunes','martes','miércoles','jueves','viernes','sábado','domingo'];
  v_choque record;
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  -- 2 · CAMBIO DE HORARIO con anotadas: bloqueado.
  if new.fecha is distinct from old.fecha then
    select count(*) into v_anotadas
      from public.reservas r
     where r.clase_id = new.id
       and coalesce(r.estado,'') in ('confirmada','pre_confirmada','presente');

    if v_anotadas > 0 then
      raise exception
        'No podés cambiar el horario de esta clase: tiene % alumna(s) anotada(s). Cancelala —se les devuelven los créditos y se les avisa solo— y creá una nueva en el horario correcto.',
        v_anotadas;
    end if;

    -- 5 · COLISIÓN: nunca dos clases del estudio en el mismo minuto y la misma
    -- sala. Misma clave que el generador y el guard de grillas
    -- (lower(trim(sala))). No se filtran canceladas: es la misma regla que ya
    -- aplica el generador, y una cancelada en ese minuto igual confunde.
    select c2.id, c2.nombre into v_choque
      from public.clases c2
     where c2.estudio_id = new.estudio_id
       and c2.id <> new.id
       and c2.fecha = new.fecha
       and lower(trim(coalesce(c2.sala,''))) = lower(trim(coalesce(new.sala,'')))
     limit 1;

    if found then
      raise exception
        'No se puede mover a ese horario: ya tenés otra clase ("%") el % a las % en la misma sala. Dos clases no pueden estar en el mismo minuto.',
        v_choque.nombre,
        v_dias[extract(isodow from new.fecha)::int] || ' ' || to_char(new.fecha,'DD/MM'),
        to_char(new.fecha,'HH24:MI');
    end if;
  end if;

  -- 4 · BAJAR EL CUPO por debajo de las anotadas: bloqueado con el número.
  if new.lugares_total is distinct from old.lugares_total then
    select count(*) into v_anotadas
      from public.reservas r
     where r.clase_id = new.id
       and coalesce(r.estado,'') in ('confirmada','pre_confirmada','presente');

    if coalesce(new.lugares_total, 0) < v_anotadas then
      raise exception
        'Hay % alumna(s) anotada(s) en esta clase: no podés dejar % lugar(es). Si no vas a dictarla, cancelala y se les devuelven los créditos.',
        v_anotadas, coalesce(new.lugares_total, 0);
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_clases_guard_cambios_anotadas on public.clases;
create trigger trg_clases_guard_cambios_anotadas
  before update on public.clases
  for each row execute function public.clases_guard_cambios_con_anotadas();

-- ----------------------------------------------------------------------------
-- B · Guard de GRILLA (punto 1): dentro del trigger que mueve. Antes de tocar
--     nada, junta las clases futuras con anotadas y arma el mensaje con el
--     detalle concreto (qué días, cuántas en cada una) y la salida.
--     Si no hay ninguna, mueve como siempre (el caso normal no cambia).
-- ----------------------------------------------------------------------------
create or replace function public.horarios_fijos_mover_clases()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
declare
  v_hora    int;
  v_minuto  int;
  v_detalle text;
  v_n       int;
  v_dias constant text[] :=
    array['lunes','martes','miércoles','jueves','viernes','sábado','domingo'];
begin
  -- Solo actuamos si cambio CUANDO se dicta la clase. El resto de los campos
  -- (profe, cupo, creditos, categorias...) ya los propaga el cliente en
  -- `_propagarHorarioFijoAClasesFuturas`, y no queremos tocar fechas al pedo.
  if new.dia_semana  is not distinct from old.dia_semana
 and new.hora_inicio is not distinct from old.hora_inicio then
    return new;
  end if;

  if new.dia_semana is null or new.dia_semana < 1 or new.dia_semana > 7 then
    return new;
  end if;

  -- BLOQUEO (2026-08-28, decisión de la usuaria): si alguna clase futura de
  -- esta grilla tiene alumnas anotadas, el movimiento se rechaza ENTERO con
  -- el detalle de cuáles. La alumna nunca se entera de un horario que cambió
  -- debajo de sus pies porque el horario no cambia. La salida es el camino
  -- que ya existe: cancelar esas clases (devuelve créditos + avisa) y mover
  -- después. Aura por SQL (current_user postgres/service_role) pasa igual.
  if current_user in ('authenticated', 'anon') then
    select count(*),
           string_agg(
             v_dias[extract(isodow from x.fecha)::int] || ' ' ||
             to_char(x.fecha,'DD/MM') || ' (' || x.n || ' anotada' ||
             case when x.n > 1 then 's' else '' end || ')',
             ', ' order by x.fecha)
      into v_n, v_detalle
      from (
        select c.fecha, count(r.id) as n
          from public.clases c
          join public.reservas r on r.clase_id = c.id
               and coalesce(r.estado,'') in ('confirmada','pre_confirmada','presente')
         where c.horario_fijo_id = new.id
           and c.fecha >= (now() at time zone 'America/Argentina/Buenos_Aires')::date
         group by c.fecha
      ) x;

    if v_n > 0 then
      raise exception
        'No podés mover esta grilla: % clase(s) tienen alumnas anotadas — %. Cancelá esa(s) clase(s) —se les devuelven los créditos y se les avisa solo— y después movela.',
        v_n, v_detalle;
    end if;
  end if;

  v_hora   := coalesce(extract(hour   from new.hora_inicio)::int, 8);
  v_minuto := coalesce(extract(minute from new.hora_inicio)::int, 0);

  -- Se MUEVEN las clases futuras de esta grilla, en su misma semana.
  -- `date_trunc('week', ...)` da el lunes, que es el mismo ancla que usa
  -- `generar_clases_estudio` (`v_week_start := hoy - (isodow - 1)`), asi que
  -- la fecha resultante es identica a la que generaria la grilla nueva. Por
  -- eso, cuando el cliente vuelve a generar, el chequeo de existencia
  -- (horario_fijo_id + fecha ±1 hora) las encuentra y las saltea: los
  -- duplicados no llegan a nacer.
  --
  -- Las PASADAS no se tocan: son historia, y de ahi cuelgan asistencias y
  -- liquidaciones.
  --
  -- La COLISIÓN (caer en el minuto de otra clase) la frena el guard por fila
  -- `trg_clases_guard_cambios_anotadas`, que corre dentro de este UPDATE.
  update public.clases c
     set fecha = (date_trunc('week', c.fecha)::date + (new.dia_semana - 1))::timestamp
                 + make_interval(hours => v_hora, mins => v_minuto)
   where c.horario_fijo_id = new.id
     and c.fecha >= (now() at time zone 'America/Argentina/Buenos_Aires')::date;

  return new;
end
$function$;

-- ----------------------------------------------------------------------------
-- C · Borrar la grilla (punto 3): las clases futuras CON reservas se cancelan
--     con devolución y aviso (el camino probado de estudio_cancelar_clase);
--     las futuras SIN reservas se borran. Las pasadas no se tocan (historia:
--     asistencias y liquidaciones cuelgan de ahí; quedan huérfanas por el
--     ON DELETE SET NULL, que para una clase pasada es correcto).
--     Antes: borrar la grilla dejaba las futuras HUÉRFANAS PERO VIVAS,
--     publicadas y tomando reservas, invisibles en "Horarios fijos".
-- ----------------------------------------------------------------------------
create or replace function public.horarios_fijos_borrar_ordenado()
returns trigger
language plpgsql
set search_path to 'public'
as $$
declare
  v_c   record;
  v_res jsonb;
begin
  if current_user not in ('authenticated', 'anon') then
    return old;
  end if;

  for v_c in
    select c.id
      from public.clases c
     where c.horario_fijo_id = old.id
       and c.fecha >= (now() at time zone 'America/Argentina/Buenos_Aires')::date
  loop
    if exists (
      select 1 from public.reservas r
       where r.clase_id = v_c.id
         and coalesce(r.estado,'') in ('confirmada','pre_confirmada','presente','completada')
    ) then
      -- Con gente: se cancela (devuelve créditos a las activas + campanita) y
      -- la clase queda como registro, cancelada. La función ya valida que
      -- quien borra sea admin del estudio.
      v_res := public.estudio_cancelar_clase(v_c.id);
      if not coalesce((v_res->>'ok')::boolean, false) then
        raise exception
          'No se pudo borrar la grilla: una clase con alumnas no se pudo cancelar (%).',
          coalesce(v_res->>'error','error');
      end if;
    else
      -- Vacía: se borra de verdad (el candado de borrado la deja pasar).
      delete from public.clases where id = v_c.id;
    end if;
  end loop;

  return old;
end;
$$;

drop trigger if exists trg_horarios_fijos_borrar_ordenado on public.horarios_fijos;
create trigger trg_horarios_fijos_borrar_ordenado
  before delete on public.horarios_fijos
  for each row execute function public.horarios_fijos_borrar_ordenado();
