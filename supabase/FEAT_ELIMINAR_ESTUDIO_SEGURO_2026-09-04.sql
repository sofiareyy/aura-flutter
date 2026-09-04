-- ============================================================================
-- ELIMINAR UN ESTUDIO, PERO SEGURO — 4/9/2026
--
-- Lo que había: un cartel de dos botones y una RPC que borraba todo con un
-- solo argumento. Medido en rollback sobre Citra el 3/9: se iban 391 clases,
-- 5 reservas, 2 reseñas y 3 accesos con un toque, y una alumna con reserva
-- FUTURA viva perdía sus 18 créditos en silencio (ni devolución ni aviso).
--
-- Decisión de la usuaria (4/9): se mantiene "eliminar" pero con tres capas.
--   1. El NOMBRE del estudio escrito, exigido también acá en la base: ningún
--      cliente puede borrar con una sola llamada por accidente.
--   2. Un resumen previo con números (reservas, liquidaciones, alumnas con
--      reserva futura) para que el cartel avise fuerte y empuje a DESACTIVAR.
--   3. Cuando SÍ se borra, no queda plata huérfana: las reservas futuras vivas
--      se cancelan como lo hace estudio_cancelar_clase (devolución de créditos
--      al ledger + campanita), y recién después cae todo en cascada.
--
-- Lo que queda A PROPÓSITO: las filas de reservas_estado_log (no tienen FK).
-- Es el registro de auditoría de que existieron y de que se borraron. Sin
-- mail: cancelacion-email lee la clase por id después del commit y ya no
-- estaría. La campanita lleva nombre, fecha y el motivo.
-- ============================================================================

-- ── 1 · el resumen que ve Sofía antes de decidir ────────────────────────────
create or replace function public.admin_estudio_resumen_borrado(p_estudio_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_ahora_ar timestamp := (now() at time zone 'America/Argentina/Buenos_Aires');
  v_e record;
  v_reservas int; v_vivas int; v_creditos bigint; v_alumnas int;
  v_liq int; v_liq_pagadas int; v_monto_pagado bigint;
  v_clases int; v_futuras int; v_resenas int; v_accesos int;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  select id, nombre, activo into v_e from public.estudios where id = p_estudio_id;
  if v_e is null then
    raise exception 'El estudio no existe';
  end if;

  select count(*), count(*) filter (where c.fecha >= v_ahora_ar)
    into v_clases, v_futuras
    from public.clases c where c.estudio_id = p_estudio_id;

  select count(*),
         count(*) filter (where c.fecha >= v_ahora_ar and r.estado in ('confirmada','presente','pre_confirmada')),
         coalesce(sum(r.creditos_usados) filter (where c.fecha >= v_ahora_ar and r.estado in ('confirmada','presente','pre_confirmada') and r.usuario_id is not null), 0),
         count(distinct r.usuario_id) filter (where c.fecha >= v_ahora_ar and r.estado in ('confirmada','presente','pre_confirmada') and r.usuario_id is not null)
    into v_reservas, v_vivas, v_creditos, v_alumnas
    from public.reservas r join public.clases c on c.id = r.clase_id
   where c.estudio_id = p_estudio_id;

  select count(*), count(*) filter (where estado = 'pagado'),
         coalesce(sum(monto_a_pagar) filter (where estado = 'pagado'), 0)
    into v_liq, v_liq_pagadas, v_monto_pagado
    from public.liquidaciones where estudio_id = p_estudio_id;

  select count(*) into v_resenas from public.study_reviews where estudio_id = p_estudio_id;
  select count(*) into v_accesos from public.estudio_admins where estudio_id = p_estudio_id;

  return jsonb_build_object(
    'id',                    v_e.id,
    'nombre',                v_e.nombre,
    'activo',                coalesce(v_e.activo, true),
    'clases',                v_clases,
    'clases_futuras',        v_futuras,
    'reservas',              v_reservas,
    'reservas_futuras_vivas', v_vivas,
    'creditos_a_devolver',   v_creditos,
    'alumnas_afectadas',     v_alumnas,
    'liquidaciones',         v_liq,
    'liquidaciones_pagadas', v_liq_pagadas,
    'monto_pagado',          v_monto_pagado,
    'resenas',               v_resenas,
    'accesos',               v_accesos,
    -- "Historial de plata": hubo reservas (cobradas o por cobrar) o liquidaciones.
    'tiene_historial',       (v_reservas > 0 or v_liq > 0)
  );
end;
$function$;
revoke execute on function public.admin_estudio_resumen_borrado(bigint) from public, anon;
grant  execute on function public.admin_estudio_resumen_borrado(bigint) to authenticated, service_role;

-- ── 2 · desactivar desde el mismo cartel ─────────────────────────────────────
-- El superadmin no siempre es miembro del estudio, y la única policy UPDATE
-- de `estudios` es para miembros: un update directo puede afectar 0 filas en
-- silencio. Por eso va por RPC. Reversible: el mismo RPC con true.
create or replace function public.admin_set_estudio_activo(p_estudio_id bigint, p_activo boolean)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_nombre text;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  update public.estudios set activo = coalesce(p_activo, true)
   where id = p_estudio_id returning nombre into v_nombre;
  if v_nombre is null then
    raise exception 'El estudio no existe';
  end if;
  perform public.log_admin_action(
    case when coalesce(p_activo, true) then 'Activar estudio' else 'Desactivar estudio' end,
    v_nombre || ' (#' || p_estudio_id || ')', 'estudios');
  return jsonb_build_object('ok', true, 'nombre', v_nombre, 'activo', coalesce(p_activo, true));
end;
$function$;
revoke execute on function public.admin_set_estudio_activo(bigint, boolean) from public, anon;
grant  execute on function public.admin_set_estudio_activo(bigint, boolean) to authenticated, service_role;

-- ── 3 · el borrado, con el nombre como llave y sin plata huérfana ────────────
-- Se DROPea la firma de un solo argumento: que NO exista un camino sin nombre.
drop function if exists public.admin_delete_estudio(bigint);

create or replace function public.admin_delete_estudio(
  p_estudio_id          bigint,
  p_nombre_confirmacion text
) returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_ahora_ar  timestamp   := (now() at time zone 'America/Argentina/Buenos_Aires');
  v_ahora     timestamptz := now();
  v_nombre    text;
  v_r         record;
  v_clases    int := 0;
  v_reservas  int := 0;
  v_liq       int := 0;
  v_devueltas int := 0;
  v_creditos  bigint := 0;
  v_avisadas  int := 0;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  select nombre into v_nombre from public.estudios where id = p_estudio_id;
  if v_nombre is null then
    raise exception 'El estudio no existe';
  end if;

  -- LA LLAVE: el nombre exacto (sin distinguir mayúsculas ni espacios de más).
  if lower(trim(coalesce(p_nombre_confirmacion, ''))) <> lower(trim(v_nombre)) then
    raise exception 'Para eliminar "%" hay que escribir su nombre exacto.', v_nombre;
  end if;

  select count(*) into v_clases from public.clases where estudio_id = p_estudio_id;
  select count(*) into v_reservas
    from public.reservas r join public.clases c on c.id = r.clase_id
   where c.estudio_id = p_estudio_id;
  select count(*) into v_liq from public.liquidaciones where estudio_id = p_estudio_id;

  -- 3a · Las reservas FUTURAS vivas se cancelan como una clase cancelada:
  --      créditos de vuelta al ledger + campanita. Mismos parámetros que
  --      estudio_cancelar_clase (vencimiento a 90 días, misma fuente).
  for v_r in
    select r.id, r.usuario_id, r.creditos_usados, c.nombre as clase, c.fecha
      from public.reservas r join public.clases c on c.id = r.clase_id
     where c.estudio_id = p_estudio_id
       and c.fecha >= v_ahora_ar
       and r.estado in ('confirmada', 'presente', 'pre_confirmada')
     for update of r
  loop
    if v_r.usuario_id is not null and coalesce(v_r.creditos_usados, 0) > 0 then
      perform public.grant_user_credits(
        v_r.usuario_id,
        v_r.creditos_usados::int,
        'devolucion_clase_cancelada',
        (v_ahora + interval '90 days')::text,
        'Devolución: ' || v_nombre || ' ya no está en Aura (' || coalesce(v_r.clase, 'clase') || ')'
      );
      v_creditos := v_creditos + v_r.creditos_usados;
    end if;
    update public.reservas set estado = 'cancelada_por_estudio' where id = v_r.id;
    v_devueltas := v_devueltas + 1;
    if v_r.usuario_id is not null then
      insert into public.notificaciones_usuario (usuario_id, titulo, mensaje, tipo, leida)
      values (v_r.usuario_id, '❌ Clase cancelada',
              'Se canceló "' || coalesce(v_r.clase, 'la clase') || '" del ' ||
              to_char(v_r.fecha, 'DD/MM') || ': ' || v_nombre ||
              ' ya no está en Aura. Te devolvimos tus créditos.',
              'clase_cancelada', false);
      v_avisadas := v_avisadas + 1;
    end if;
  end loop;

  -- 3b · Cascada, en el orden que las FK exigen (clases y liquidaciones son
  --      NO ACTION sobre estudios). reservas y lista_espera caen con clases.
  delete from public.clases where estudio_id = p_estudio_id;
  delete from public.liquidaciones where estudio_id = p_estudio_id;
  update public.usuarios set estudio_id = null where estudio_id = p_estudio_id;
  delete from public.estudios where id = p_estudio_id;

  perform public.log_admin_action(
    'Eliminar estudio',
    v_nombre || ' (#' || p_estudio_id || ') · ' || v_clases || ' clases, ' ||
      v_reservas || ' reservas, ' || v_liq || ' liquidaciones, ' ||
      v_creditos || ' créditos devueltos a ' || v_avisadas || ' alumna(s)',
    'estudios'
  );

  return jsonb_build_object(
    'ok',                  true,
    'nombre',              v_nombre,
    'clases',              v_clases,
    'reservas',            v_reservas,
    'liquidaciones',       v_liq,
    'reservas_canceladas', v_devueltas,
    'creditos_devueltos',  v_creditos,
    'alumnas_avisadas',    v_avisadas
  );
end;
$function$;
revoke execute on function public.admin_delete_estudio(bigint, text) from public, anon;
grant  execute on function public.admin_delete_estudio(bigint, text) to authenticated, service_role;

notify pgrst, 'reload schema';

-- ── Verificación ────────────────────────────────────────────────────────────
--   select proname, pg_get_function_arguments(oid) from pg_proc
--    where proname in ('admin_delete_estudio','admin_estudio_resumen_borrado','admin_set_estudio_activo');
--   ⇒ admin_delete_estudio con UNA firma de 2 parámetros.
