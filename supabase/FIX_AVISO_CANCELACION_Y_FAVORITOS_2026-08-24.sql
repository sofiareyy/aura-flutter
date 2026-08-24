-- ============================================================================
-- AURA — El aviso de clase cancelada que nunca llegaba + re-favoritear
-- ============================================================================
-- Aplicado a mano vía la Management API el 2026-08-24 (segunda tanda del día).
-- Sin Dart ⇒ sin build.
--
-- Salió de auditar las tandas ANTERIORES con el criterio de las dos puntas,
-- después de reparar las del 20/8. Resultado de esa auditoría: 110 funciones
-- de `public` (62 las llama la app), 23 tablas y 3 buckets revisados. **No
-- había más guards mal validados.** Estos dos huecos son más viejos que las
-- tandas de endurecimiento y nunca los reportó nadie.
--
-- ── H1: la alumna no se enteraba de que le cancelaban la clase ──────────────
-- `notificaciones_usuario` tiene policies de SELECT y UPDATE, **ninguna de
-- INSERT**. `reservas_service.dart:593` insertaba ahí el aviso
-- "❌ Clase cancelada" para cada alumna afectada; RLS lo rechazaba con 42501 y
-- el `catch (_) {}` se lo tragaba. Verificado que no se recuperaba por ningún
-- otro lado: las únicas funciones que escriben en esa tabla son
-- `_notify_profes_nueva_reserva_interno` (reserva_profe),
-- `_waitlist_promote_interno` (pre_confirmada) y `enviar_aviso_estudio`
-- (aviso_general/urgente). Ninguna usa el tipo 'clase_cancelada' — en
-- `estudio_cancelar_clase` ese texto aparecía sólo dentro de
-- 'devolucion_clase_cancelada', que es el `source` del movimiento de créditos.
-- Resultado: le devolvían los créditos y no le avisaban nada.
--
-- NO es un guard mal validado: la tabla nunca tuvo policy de INSERT (el
-- comentario de `_waitlist_promote_interno` ya lo documentaba). Lo que pasó es
-- que el hueco **se volvió alcanzable hoy**: hasta esta mañana
-- `estudio_cancelar_clase` moría en el 42883 antes de hacer nada.
--
-- Arreglo: que la función cree la campanita adentro. Es SECURITY DEFINER, así
-- que saltea RLS — mismo patrón que el aviso a la profe. El insert va en su
-- propio bloque `begin/exception`: si el aviso falla, la DEVOLUCIÓN no se cae.
-- La policy de INSERT se deja como estaba, cerrada: nadie puede fabricar
-- notificaciones, ni siquiera para sí mismo.
--
-- ── H2: re-favoritear un estudio ya marcado fallaba ─────────────────────────
-- Ver el comentario del bloque B.
--
-- ── Las dos puntas, midiendo efecto ────────────────────────────────────────
--   H1 legítima → el estudio cancela: créditos de la alumna 0→10 **y**
--                 campanita 0→1 con el texto correcto. Antes: créditos sí,
--                 campanita 0.
--   H1 cerrada  → la alumna insertando en notificaciones_usuario para otra
--                 usuaria → 42501; para sí misma → 42501. Igual que antes.
--   H1 no rompe → aviso a la profe sigue en 1; aviso general del estudio
--                 sigue ok; lista de espera: profe 1 y promovida 1.
--   H1 bordes   → clase gratis (0 créditos): el texto NO promete devolución.
--                 Dos alumnas en la misma clase: 2 campanitas, créditos a las
--                 dos.
--   H2          → 42501 → pasa. 
-- Probado con `citrabarre@gmail.com` (estudio real, NO superadmin). Todo en
-- transacciones con rollback; verificado que quedaron 0 filas y 0 pushes
-- encolados.
--
-- ⚠️ OJO al probar esta tabla: `trg_notif_push_nueva` está ACTIVO y dispara
-- `net.http_post` a la edge function `push-enviar`. Se comprobó que el push se
-- encola DENTRO de la transacción y que el rollback lo borra (cola 0→1→0), así
-- que probar con rollback es seguro. Sin esa comprobación, un test manda un
-- push real al teléfono de alguien.
--
-- ============================================================================
-- BLOQUE A — H1: estudio_cancelar_clase crea la campanita
-- ============================================================================

CREATE OR REPLACE FUNCTION public.estudio_cancelar_clase(p_clase_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid       uuid := auth.uid();
  v_clase     record;
  v_r         record;
  v_afectados int := 0;
  v_creditos  int := 0;
  v_ahora     timestamp := (
    now() at time zone 'America/Argentina/Buenos_Aires'
  );
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'no_auth');
  end if;

  select * into v_clase from public.clases where id = p_clase_id;
  if v_clase is null then
    return jsonb_build_object('ok', false, 'error', 'clase_no_encontrada');
  end if;

  -- Solo admin del estudio. Una profe no cancela clases.
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
    if coalesce(v_r.creditos_usados, 0) > 0 then
      perform public.grant_user_credits(
        v_r.usuario_id,
        v_r.creditos_usados::int,   -- 2026-08-24: la columna es bigint y
                                    -- grant_user_credits toma integer (42883)
        'devolucion_clase_cancelada',
        (v_ahora + interval '90 days')::text,
        'Devolución por clase cancelada: ' || coalesce(v_clase.nombre, 'clase')
      );
      v_creditos := v_creditos + v_r.creditos_usados;
    end if;

    update public.reservas
       set estado = 'cancelada_por_estudio'
     where id = v_r.id;

    -- 2026-08-24: la campanita la crea la FUNCION, no el cliente.
    -- `reservas_service.dart:593` insertaba este aviso en notificaciones_usuario
    -- para OTRO usuario, y RLS lo negaba con 42501 (esa tabla solo tiene
    -- policies de SELECT y UPDATE, ninguna de INSERT). El error quedaba tragado
    -- por su `catch (_) {}`: a la alumna le devolvian los creditos y nunca se
    -- enteraba de que le habian cancelado la clase. Ninguna funcion de la base
    -- creaba este aviso — verificado: las unicas que escriben en esa tabla son
    -- _notify_profes_nueva_reserva_interno, _waitlist_promote_interno y
    -- enviar_aviso_estudio, y ninguna usa el tipo 'clase_cancelada'.
    -- Aca es SECURITY DEFINER, asi que saltea RLS. Mismo patron que el aviso a
    -- la profe. En bloque propio: si el aviso falla, la DEVOLUCION no se cae.
    begin
      insert into public.notificaciones_usuario (usuario_id, titulo, mensaje, tipo, leida)
      values (
        v_r.usuario_id,
        '❌ Clase cancelada',
        'Se canceló "' || coalesce(v_clase.nombre, 'una clase') || '".' ||
          case when coalesce(v_r.creditos_usados, 0) > 0
               then ' Te devolvimos tus créditos.'
               else '' end,
        'clase_cancelada',
        false
      );
    exception when others then
      null;
    end;

    v_afectados := v_afectados + 1;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'reservas_canceladas', v_afectados,
    'creditos_devueltos', v_creditos
  );
end;
$function$;

-- ============================================================================
-- BLOQUE B — H2: policy de UPDATE en favoritos_estudios
-- ============================================================================

-- H2: `favoritos_estudios` tenia policies de INSERT, SELECT y DELETE pero
-- ninguna de UPDATE, y `favoritos_service.dart:28` hace `.upsert()` sobre la PK
-- (usuario_id, estudio_id). Si la fila YA existe, Postgres resuelve el conflicto
-- con un UPDATE y RLS lo rechaza con 42501. Se dispara con estado desincronizado:
-- doble tap, dos dispositivos, pantalla desactualizada.
-- No agrega capacidad nueva: la usuaria ya podia borrar e insertar sus propios
-- favoritos, y el WITH CHECK la deja encerrada en sus propias filas.
drop policy if exists favoritos_estudios_update_self on public.favoritos_estudios;
create policy favoritos_estudios_update_self on public.favoritos_estudios
  for update
  using (auth.uid() = usuario_id)
  with check (auth.uid() = usuario_id);
