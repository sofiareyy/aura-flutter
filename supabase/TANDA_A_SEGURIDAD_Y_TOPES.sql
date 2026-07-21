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
