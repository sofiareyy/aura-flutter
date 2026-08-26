-- Paso 3 de preservar facturación: la red de seguridad de esquema.
--
-- ✅ APLICADO EN PRODUCCIÓN el 2026-08-26, en el orden de abajo: primero el
-- prerrequisito (3.0), después las FK (3.1).
--
-- Verificado después de aplicar:
--   · cancelar una clase con una reserva huérfana: ok, 2 reservas afectadas y
--     sólo 12 créditos devueltos (la huérfana se saltea, la real cobra).
--   · cancelar una clase normal: idéntico a antes.
--   · borrar una fila de `usuarios` por SQL directo: Citra conserva sus 36 por
--     cobrar y el ledger sus 16 movimientos. Con CASCADE, medido en la misma
--     transacción, daba 0 y 0.
--   · base sana: 85 = 85, 2 reservas, 1320 clases, 0 huérfanas reales.
--
-- CONTEXTO: el agujero YA está tapado por la edge function `delete-account`
-- v10 (26/8), que en vez de borrar la fila de `usuarios` la anonimiza. Esto es
-- la red para el otro camino: que alguien borre una fila de `usuarios` por SQL
-- directo, o desde `admin_delete_estudio`.

-- ============================================================================
-- 3.0 · PRERREQUISITO — sin esto, el paso 3 ROMPE algo que hoy funciona
-- ============================================================================
-- Medido el 26/8 con una reserva de usuario_id NULL:
--   estudio_cancelar_clase ⇒ ERROR "grant_user_credits: p_user_id es null"
-- La cancelación ENTERA falla. O sea: si un estudio quisiera cancelar una
-- clase que tiene una reserva de una cuenta borrada, no podría, y el mensaje
-- no le diría por qué. Hay que saltear las huérfanas ANTES de tocar las FK.

create or replace function public.estudio_cancelar_clase(p_clase_id bigint)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
  v_clase public.clases%rowtype;
  v_r public.reservas%rowtype;
  v_ahora timestamptz := now();
  v_creditos bigint := 0;
  v_afectadas int := 0;
begin
  select * into v_clase from public.clases where id = p_clase_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'clase_inexistente');
  end if;
  if coalesce(v_clase.cancelada, false) then
    return jsonb_build_object('ok', false, 'error', 'ya_cancelada');
  end if;

  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'sin_sesion');
  end if;

  if not exists (
    select 1 from public.estudio_admins ea
     where ea.estudio_id = v_clase.estudio_id
       and ea.usuario_id = v_uid
       and ea.rol in ('estudio', 'admin_estudio')
  ) then
    return jsonb_build_object('ok', false, 'error', 'sin_permisos');
  end if;

  for v_r in
    select * from public.reservas
     where clase_id = p_clase_id
       and estado in ('confirmada', 'presente', 'pre_confirmada')
     for update
  loop
    -- 2026-08-26: `usuario_id` puede ser NULL (reserva de una cuenta borrada,
    -- conservada como evidencia de cobro). No hay a quién devolverle los
    -- créditos: se saltea la devolución, pero la reserva SÍ se cancela.
    -- Sin este guard, grant_user_credits tira "p_user_id es null" y se cae la
    -- cancelación entera.
    if v_r.usuario_id is not null and coalesce(v_r.creditos_usados, 0) > 0 then
      perform public.grant_user_credits(
        v_r.usuario_id,
        v_r.creditos_usados::int,
        'devolucion_clase_cancelada',
        (v_ahora + interval '90 days')::text,
        'Devolución por clase cancelada: ' || coalesce(v_clase.nombre, 'clase')
      );
      v_creditos := v_creditos + v_r.creditos_usados;
    end if;

    update public.reservas set estado = 'cancelada_por_estudio' where id = v_r.id;
    v_afectadas := v_afectadas + 1;

    if v_r.usuario_id is not null then
      insert into public.notificaciones_usuario (usuario_id, titulo, mensaje, tipo, leida)
      values (v_r.usuario_id, '❌ Clase cancelada',
              'Se canceló "' || coalesce(v_clase.nombre, 'la clase') ||
              '". Te devolvimos tus créditos.', 'clase_cancelada', false);
    end if;
  end loop;

  update public.clases set cancelada = true where id = p_clase_id;

  return jsonb_build_object('ok', true, 'reservas_afectadas', v_afectadas,
                            'creditos_devueltos', v_creditos);
end;
$$;

-- ============================================================================
-- 3.1 · Las FK: de CASCADE a SET NULL
-- ============================================================================
-- Grupo A (evidencia de plata) + admin_activity_logs (log de auditoría: un log
-- que el auditado puede borrar no sirve como auditoría).
-- `study_reviews` NO entra: con el modelo de lápida la reseña ya queda como
-- "Anónimo" sin tocar el esquema.

alter table public.reservas             alter column usuario_id   drop not null;
alter table public.pagos                alter column user_id      drop not null;
alter table public.creditos_movimientos alter column user_id      drop not null;
alter table public.admin_activity_logs  alter column admin_user_id drop not null;

alter table public.reservas drop constraint reservas_usuario_id_fkey;
alter table public.reservas add constraint reservas_usuario_id_fkey
  foreign key (usuario_id) references public.usuarios(id) on delete set null;

alter table public.pagos drop constraint pagos_user_id_fkey;
alter table public.pagos add constraint pagos_user_id_fkey
  foreign key (user_id) references public.usuarios(id) on delete set null;

alter table public.creditos_movimientos drop constraint creditos_movimientos_user_id_fkey;
alter table public.creditos_movimientos add constraint creditos_movimientos_user_id_fkey
  foreign key (user_id) references public.usuarios(id) on delete set null;

alter table public.admin_activity_logs drop constraint admin_activity_logs_admin_user_id_fkey;
alter table public.admin_activity_logs add constraint admin_activity_logs_admin_user_id_fkey
  foreign key (admin_user_id) references public.usuarios(id) on delete set null;


-- ============================================================================
-- ⚠️ LO QUE ESTO NO CIERRA — medido el 26/8 después de aplicar
-- ============================================================================
-- `admin_delete_estudio` SIGUE destruyendo la facturación, y por otra puerta:
-- hace `delete from public.clases where estudio_id = ...`, y `reservas.clase_id`
-- es ON DELETE CASCADE — un cascade DISTINTO del de `usuario_id`, que es el que
-- arreglamos acá. Además hace `delete from public.liquidaciones`.
--
-- Medido con Citra en una transacción con rollback: sus 36 créditos por cobrar
-- pasan a 0 y las 2 reservas desaparecen.
--
-- No se tocó porque borrar un estudio entero es una acción deliberada de
-- superadmin y tiene su propia confirmación, pero conviene decidir si el
-- histórico de facturación de un estudio dado de baja tiene que sobrevivir
-- (para la contadora, o por si se le quedó debiendo plata).
-- Opciones: `reservas.clase_id` a SET NULL, o que `admin_delete_estudio`
-- archive en vez de borrar.
