-- ============================================================================
-- AURA — El estudio no puede resucitar una reserva cancelada
-- ============================================================================
-- (2026-08-22) Tanda A. Cierra el pendiente de WHITELIST_ESTADOS_ESTUDIO.md.
--
-- EL RIESGO
-- El fix del 21/8 (FIX_RESERVAS_ESCRITURA_CLIENTE) cerro la escritura directa
-- del cliente sobre `reservas`, pero dejo A PROPOSITO que el estudio escriba
-- `estado` y `checked_in_at`: los necesita para el escaner de QR y para
-- cancelar.
--
-- El agujero residual: un estudio podia dar vuelta una reserva
-- 'cancelada' -> 'presente'. Y 'presente' esta en estadosLiquidables, o sea
-- que esa reserva se factura. El estudio podia inflar su propia liquidacion.
--
-- Acotado, pero real: `creditos_usados` ya estaba bloqueado para todos, asi
-- que el estudio no puede cambiar CUANTO vale cada reserva — solo CUANTAS
-- entran a la liquidacion.
--
-- EL ARREGLO
-- Una guarda en el trigger que YA existe, dentro de la rama del estudio. No
-- hace falta trigger nuevo. Prohibe UNA sola cosa: salir de un estado muerto
-- ('cancelada' / 'cancelada_por_estudio') hacia cualquier otro.
--
-- NO CIERRA DE MAS. Se relevaron las transiciones reales del escaner
-- (asistencia_screen.dart): _marcarAsistente() se llama con 'presente',
-- 'ausente' y 'confirmada'. Esa tercera es el "deshacer" cuando el estudio
-- marco mal, y tenia que seguir funcionando. Sigue.
--
-- SE COMPLEMENTA CON EL ARREGLO DEL INDICE (20260822200000)
-- Prohibir la resurreccion solo es justo si la alumna tiene otra salida. La
-- tiene: desde aquel fix, una reserva cancelada ya no ocupa el lugar unico de
-- `reservas_usuario_clase_uidx`, asi que puede volver a reservar la clase
-- desde la app. En el orden inverso la habriamos dejado trabada.
--
-- VERIFICADO — 9 puntas con rollback, y de nuevo contra el trigger ya aplicado
--   siguen andando:  confirmada->presente, presente->ausente,
--                    ausente->presente, presente->confirmada (deshacer),
--                    confirmada->cancelada
--   bloqueadas:      cancelada->presente, cancelada->confirmada,
--                    cancelada_por_estudio->completada
--   y la alumna re-reserva la clase sin problema
--   produccion intacta: 5 reservas, 885 clases
--
-- PENDIENTE RELACIONADO (decision de la usuaria: no ahora)
-- `reservas` no tiene historial de cambios de estado. Sin log no hay forma de
-- DETECTAR el abuso a posteriori, solo de prevenirlo. Cuando la liquidacion
-- mueva plata real y haya mas volumen, conviene una tabla de log antes que
-- endurecer mas el trigger.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.reservas_bloquear_columnas_sensibles()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_es_estudio boolean;
begin
  -- Solo frenamos la escritura DIRECTA del cliente. Las RPC security definer
  -- (owned by postgres) y el service_role corren con otro current_user y pasan.
  if current_user not in ('authenticated', 'anon') then return new; end if;

  -- El estudio de la clase (cualquier rol en estudio_admins) marca asistencia.
  v_es_estudio := public.puede_ver_reservas_de_clase(old.clase_id);

  -- Columnas que NADIE toca desde el cliente, ni la alumna ni el estudio.
  if new.id              is distinct from old.id
  or new.usuario_id      is distinct from old.usuario_id
  or new.clase_id        is distinct from old.clase_id
  or new.creditos_usados is distinct from old.creditos_usados
  or new.codigo_qr       is distinct from old.codigo_qr
  or new.created_at      is distinct from old.created_at
  or new.expires_at      is distinct from old.expires_at then
    raise exception 'Esa columna de la reserva no se edita desde el cliente';
  end if;

  -- estado / checked_in_at: solo el estudio (asistencia). La alumna cancela
  -- por cancelar_mi_reserva, nunca por UPDATE directo.
  if (new.estado is distinct from old.estado
      or new.checked_in_at is distinct from old.checked_in_at)
     and not v_es_estudio then
    raise exception 'Tu reserva se cancela desde la app, no editando la fila';
  end if;

  -- El estudio SI mueve estados: es lo que hace el escaner de QR y la
  -- cancelacion. Lo unico que NO puede hacer es RESUCITAR una reserva muerta.
  --
  -- Por que importa: 'presente', 'ausente', 'confirmada' y 'completada' estan
  -- en estadosLiquidables, o sea que se facturan. Un estudio que diera vuelta
  -- una 'cancelada' -> 'presente' estaria inflando su propia liquidacion. No
  -- puede cambiar CUANTO vale cada reserva (creditos_usados esta bloqueado
  -- para todos, arriba), pero si CUANTAS entran.
  --
  -- Esto NO cierra de mas: las transiciones legitimas del escaner siguen
  -- todas abiertas — confirmada <-> presente <-> ausente, incluido el
  -- "deshacer" a confirmada cuando el estudio marco mal. Y cancelar tambien.
  --
  -- Y la alumna no queda sin salida: desde el arreglo del indice
  -- reservas_usuario_clase_uidx (20260822200000), una reserva cancelada ya no
  -- ocupa el lugar unico, asi que puede volver a reservar la clase desde la
  -- app. Antes de ese fix, prohibir la resurreccion la habria dejado trabada.
  if v_es_estudio
     and old.estado in ('cancelada', 'cancelada_por_estudio')
     and new.estado not in ('cancelada', 'cancelada_por_estudio') then
    raise exception 'Una reserva cancelada no se puede reactivar. Si la alumna quiere volver, tiene que reservar de nuevo desde la app.';
  end if;

  return new;
end $function$
;
