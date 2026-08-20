-- ============================================================================
-- AURA — Lista de espera, Tanda 1 (solo base, sin Dart)
-- ============================================================================
-- Aplicado a mano vía la Management API el 2026-08-20.
-- Plan y pendientes: supabase/pendientes/LISTA_ESPERA_arreglar_y_asegurar.md
--
-- La promoción de lista de espera estaba ROTA: fallaba SIEMPRE y el error se
-- lo tragaba su propio 'exception when others' devolviendo ok:false en
-- silencio. Nadie era promovido nunca cuando se liberaba un cupo.
--
-- Verificado end-to-end en transacción + rollback: 15/15 del flujo legítimo
-- y 10/10 de los exploits. Ver el pendiente para el detalle.
-- ============================================================================

-- ===========================================================================
-- LISTA DE ESPERA — Tanda 1 (solo base, sin Dart)
-- ===========================================================================
-- A: los 4 bugs que rompían la promoción (fallaba SIEMPRE, tragada por su
--    `exception when others` -> ok:false en silencio; nadie era promovido nunca)
-- A5: la campanita al promovido, desde la función (antes no se enteraba nadie)
-- B: guards de caller en promote / release / cleanup
-- C: cerrar waitlist_count_public + RPCs de conteo sin identidades
-- ===========================================================================


-- ── A + A5: el motor, en una función INTERNA sin guard ──────────────────────
-- Toda la lógica vive acá. Las dos funciones públicas de abajo la envuelven con
-- su propio guard. Es más limpio que el flag de sesión (`app.wl_internal`) que
-- se había pensado: esta función simplemente NO se puede llamar desde afuera,
-- no depende de acordarse de setear y resetear una variable.
create or replace function public._waitlist_promote_interno(
  p_clase_id integer,
  p_count integer default 1)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_wl_id          bigint;
  v_wl_usuario     text;          -- lista_espera.usuario_id es TEXT, no uuid
  v_codigo_qr      text;
  v_expires_at     timestamptz;
  v_reserva        record;
  v_promoted       jsonb := '[]'::jsonb;
  v_clase_nombre   text;
  v_estudio_nombre text;
  v_estudio_id     bigint;
  v_lugares_disp   int;
  v_lugares_total  int;
  v_remaining      int := coalesce(p_count, 1);
begin
  if p_clase_id is null then
    return jsonb_build_object('ok', false, 'error', 'clase_id_requerido');
  end if;

  -- BUG 1 ARREGLADO: el lock va sobre `clases` SOLA. Antes era
  -- `from clases c left join estudios e ... for update`, y Postgres tira
  -- "FOR UPDATE cannot be applied to the nullable side of an outer join".
  -- Ese error saltaba primero y hacía fallar toda la función.
  select c.lugares_disponibles, c.lugares_total, c.nombre, c.estudio_id
    into v_lugares_disp, v_lugares_total, v_clase_nombre, v_estudio_id
    from public.clases c
   where c.id = p_clase_id
     for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'clase_no_encontrada');
  end if;

  -- El nombre del estudio, en un select aparte y SIN lock.
  select e.nombre into v_estudio_nombre
    from public.estudios e
   where e.id = v_estudio_id;

  while v_remaining > 0 loop
    if coalesce(v_lugares_disp, v_lugares_total, 0) <= 0 then
      exit;
    end if;

    -- BUG 2 ARREGLADO: el orden es por `created_at` (orden de llegada).
    -- `lista_espera` NUNCA tuvo columna `posicion`; el `order by posicion`
    -- anterior fallaba. `id` desempata para que el orden sea determinista.
    select le.id, le.usuario_id
      into v_wl_id, v_wl_usuario
      from public.lista_espera le
     where le.clase_id = p_clase_id
     order by le.created_at asc, le.id asc
     limit 1
     for update skip locked;

    if v_wl_id is null then
      exit;
    end if;

    v_codigo_qr := 'AURA-' ||
                   upper(substring(v_wl_usuario from 1 for 8)) || '-' ||
                   p_clase_id::text || '-' ||
                   (extract(epoch from now()) * 1000)::bigint::text || '-' ||
                   lpad(floor(random() * 10000)::int::text, 4, '0');
    v_expires_at := now() + interval '30 minutes';

    insert into public.reservas (
      usuario_id, clase_id, estado, creditos_usados, codigo_qr, expires_at
    ) values (
      v_wl_usuario::uuid, p_clase_id, 'pre_confirmada', 0, v_codigo_qr, v_expires_at
    )
    returning * into v_reserva;

    update public.clases
       set lugares_disponibles = coalesce(lugares_disponibles, lugares_total, 0) - 1
     where id = p_clase_id;
    v_lugares_disp := coalesce(v_lugares_disp, v_lugares_total, 0) - 1;

    -- BUGS 3 y 4 ARREGLADOS: se borra por `id`. Antes borraba por
    -- (clase_id, usuario_id) comparando TEXT = UUID -> no existe ese operador.
    -- Y se fue el `update lista_espera set posicion = posicion - 1`, que
    -- renumeraba una columna inexistente.
    delete from public.lista_espera where id = v_wl_id;

    -- A5: la campanita la crea la FUNCIÓN, no el cliente.
    -- El cliente insertaba en notificaciones_usuario con el usuario_id de OTRO
    -- y RLS lo denegaba (esa tabla solo tiene policies de SELECT y UPDATE);
    -- el error quedaba tragado por su try/catch. Resultado: el promovido no se
    -- enteraba de nada, teniendo 30 minutos para confirmar.
    -- Acá es security definer, así que saltea RLS (mismo patrón que
    -- notify_profes_nueva_reserva).
    -- OJO: esto es la campanita IN-APP. NO es un push al celular: eso necesita
    -- FCM/APNs, que el proyecto no tiene montado. El promovido lo ve al abrir.
    insert into public.notificaciones_usuario (usuario_id, titulo, mensaje, tipo)
    values (
      v_wl_usuario::uuid,
      '¡Se liberó un lugar! ⚡',
      'Tenés 30 minutos para confirmar tu lugar en ' ||
        coalesce(v_clase_nombre, 'una clase') || ' de ' ||
        coalesce(v_estudio_nombre, 'el estudio') || '.',
      'pre_confirmada'
    );

    v_promoted := v_promoted || jsonb_build_object(
      'usuario_id',     v_wl_usuario,
      'reserva_id',     v_reserva.id,
      'codigo_qr',      v_codigo_qr,
      'expires_at',     v_expires_at,
      'clase_nombre',   v_clase_nombre,
      'estudio_nombre', v_estudio_nombre
    );

    v_remaining := v_remaining - 1;
  end loop;

  return jsonb_build_object('ok', true, 'promoted', v_promoted);

exception when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end
$fn$;

-- No ejecutable desde afuera. Solo la alcanzan las funciones security definer
-- de abajo (que corren como el owner).
revoke all on function public._waitlist_promote_interno(integer, integer)
  from public, anon, authenticated;


-- ── B: waitlist_promote_next = guard + delegar ──────────────────────────────
create or replace function public.waitlist_promote_next(
  p_clase_id integer,
  p_count integer default 1)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_uid        uuid := auth.uid();
  v_estudio_id bigint;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'no_auth');
  end if;
  if p_clase_id is null then
    return jsonb_build_object('ok', false, 'error', 'clase_id_requerido');
  end if;

  select c.estudio_id into v_estudio_id
    from public.clases c where c.id = p_clase_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'clase_no_encontrada');
  end if;

  -- Guard: que un usuario cualquiera no promueva la grilla de una clase ajena.
  -- Permitidos: admin de Aura; miembro del estudio (el panel promueve al
  -- aumentar cupo); o alguien con reserva en esa clase (el que acaba de
  -- cancelar la suya y dispara la promoción desde el cliente).
  if not (
       public.is_admin()
    or public.es_miembro_de_estudio(v_estudio_id)
    or exists (
         select 1 from public.reservas r
          where r.clase_id = p_clase_id
            and r.usuario_id = v_uid)
  ) then
    return jsonb_build_object('ok', false, 'error', 'no_autorizado');
  end if;

  return public._waitlist_promote_interno(p_clase_id, p_count);
end
$fn$;

revoke all on function public.waitlist_promote_next(integer, integer) from anon;


-- ── B: release_pre_reserva = guard + delegar ────────────────────────────────
create or replace function public.release_pre_reserva(p_reserva_id integer)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_reserva        record;
  v_promote_result jsonb;
  v_uid            uuid := auth.uid();
begin
  select * into v_reserva
    from public.reservas
   where id = p_reserva_id
   for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'reserva_no_encontrada');
  end if;

  if v_reserva.estado <> 'pre_confirmada' then
    return jsonb_build_object('ok', false, 'error', 'estado_invalido');
  end if;

  -- Guard: liberás la TUYA, o una VENCIDA (para el cleanup). Bloquea que
  -- alguien libere la pre-reserva ACTIVA de otro para robarle el lugar.
  if v_reserva.usuario_id is distinct from v_uid
     and not (v_reserva.expires_at is not null and v_reserva.expires_at < now())
  then
    return jsonb_build_object('ok', false, 'error', 'no_autorizado');
  end if;

  delete from public.reservas where id = p_reserva_id;

  update public.clases
     set lugares_disponibles = coalesce(lugares_disponibles, 0) + 1
   where id = v_reserva.clase_id;

  -- Llamada interna: sin guard, porque el guard ya se aplicó arriba.
  v_promote_result := public._waitlist_promote_interno(v_reserva.clase_id::integer, 1);

  return jsonb_build_object(
    'ok',       true,
    'clase_id', v_reserva.clase_id,
    'promoted', v_promote_result
  );

exception when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end
$fn$;

revoke all on function public.release_pre_reserva(integer) from anon;


-- ── B: cleanup solo pierde anon (el cuerpo no cambia) ──────────────────────
-- Solo toca pre_confirmadas vencidas, y pasa por el guard de release.
revoke all on function public.cleanup_pre_reservas_expiradas(integer) from anon;


-- ── C: cerrar la lectura pública de lista_espera ───────────────────────────
-- `waitlist_count_public` tenía USING true con roles {public}: cualquiera,
-- anon incluido, podía leer TODAS las filas CON usuario_id. La tabla está
-- vacía hoy, así que no hubo dato expuesto, pero quedaba armado.
drop policy if exists "waitlist_count_public" on public.lista_espera;

-- Las otras dos hacían lo mismo con distinto cast. Queda una sola.
drop policy if exists "usuario ve su lista espera" on public.lista_espera;
-- sobrevive: waitlist_own  ALL  using ((auth.uid())::text = usuario_id)


-- ── C: el conteo, sin identidades ──────────────────────────────────────────
create or replace function public.waitlist_count(p_clase_id integer)
returns integer
language sql
stable
security definer
set search_path to 'public'
as $fn$
  select count(*)::int
    from public.lista_espera
   where clase_id = p_clase_id;
$fn$;

-- Cuántos hay es info de marketplace (el invitado ya la veía); QUIÉNES son, no.
grant execute on function public.waitlist_count(integer) to anon, authenticated;


-- ── C: mi posición, derivada de created_at (reemplaza la columna inexistente)
create or replace function public.waitlist_mis_posiciones()
returns table(clase_id integer, posicion integer, total integer)
language sql
stable
security definer
set search_path to 'public'
as $fn$
  with mias as (
    select le.clase_id
      from public.lista_espera le
     where le.usuario_id = auth.uid()::text
  ),
  ranked as (
    select le.clase_id,
           le.usuario_id,
           row_number() over (partition by le.clase_id
                              order by le.created_at asc, le.id asc)::int as pos,
           count(*) over (partition by le.clase_id)::int as tot
      from public.lista_espera le
     where le.clase_id in (select clase_id from mias)
  )
  select r.clase_id, r.pos, r.tot
    from ranked r
   where r.usuario_id = auth.uid()::text
   order by r.clase_id;
$fn$;

grant execute on function public.waitlist_mis_posiciones() to authenticated;
revoke all on function public.waitlist_mis_posiciones() from anon;


-- ── Corrección de grants (el 'revoke from anon' inicial era un no-op) ──────
-- Las funciones tenían el grant a PUBLIC (=X/postgres) y anon hereda de ahí,
-- así que revocarle a anon no cambiaba nada. Hay que revocar PUBLIC.
revoke all on function public.waitlist_promote_next(integer, integer) from public;
revoke all on function public.release_pre_reserva(integer) from public;
revoke all on function public.cleanup_pre_reservas_expiradas(integer) from public;
revoke all on function public.waitlist_mis_posiciones() from public;
grant execute on function public.waitlist_promote_next(integer, integer) to authenticated, service_role;
grant execute on function public.release_pre_reserva(integer) to authenticated, service_role;
grant execute on function public.cleanup_pre_reservas_expiradas(integer) to authenticated, service_role;
grant execute on function public.waitlist_mis_posiciones() to authenticated, service_role;
-- waitlist_count SÍ conserva anon a propósito: devuelve solo el número.
