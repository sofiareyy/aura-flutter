-- =====================================================================
-- FIX: escritura directa del cliente sobre `reservas` — 2026-08-21
-- Encontrado MIDIENDO contra la base durante la auditoría pre-build.
-- No estaba en ningún pendiente. Aplicado vía Management API y
-- verificado con rollback + efecto (10/10). Solo base, sin Dart => sin build.
-- =====================================================================
--
-- CONTEXTO
-- `reservas` tenía RLS activo pero, a diferencia de `usuarios`, `estudios` y
-- `estudios_datos_cobro`, NO tenía trigger que blindara columnas. La policy
-- `reservas_update_own` (USING auth.uid() = usuario_id) era la única puerta:
-- alcanzaba con ser dueña de la fila para escribir cualquier columna.
--
-- ---------------------------------------------------------------------
-- 🔴 1. UPDATE libre sobre la propia reserva (PLATA)
-- ---------------------------------------------------------------------
-- CONFIRMADO explotable, 4 de 4 medidas con efecto real desde una usuaria
-- común autenticada (solo con la anon key pública + su cuenta):
--   - estado 'cancelada' -> 'confirmada'  => se queda con los créditos ya
--     devueltos Y recupera el lugar (doble beneficio).
--   - estado -> 'presente'               => 'presente' está en
--     AppConstants.estadosLiquidables: EL ESTUDIO FACTURA ESO.
--   - creditos_usados 14 -> 9999         => infla directo lo que cobra el
--     estudio en la liquidación.
--   - clase_id -> la clase más cara      => se mudó a una de 50 créditos
--     sin pagar la diferencia.
-- NO explotable: cambiar usuario_id de reservas ajenas (0 filas; el USING
-- acota bien). Verificado con GET DIAGNOSTICS ROW_COUNT.
--
-- ---------------------------------------------------------------------
-- 🔴 2. INSERT de reservas gratis (PLATA) — peor que el anterior
-- ---------------------------------------------------------------------
-- La policy `reservas_insert_own` sólo validaba DE QUIÉN es la fila
-- (CHECK auth.uid() = usuario_id), no qué dice. CONFIRMADO explotable:
--   INSERT estado='confirmada', creditos_usados=0 en una clase de 50
--   créditos => reserva válida, 0 créditos descontados, ledger intacto.
-- No hace falta ni tener una reserva previa que manipular: se fabrica de
-- cero, salteando `reservar_clase` por completo.
-- DELETE ya estaba cerrado (no hay policy).
--
-- ---------------------------------------------------------------------
-- QUIÉN ESCRIBE `reservas` DE VERDAD (barrido de todo lib/)
-- ---------------------------------------------------------------------
-- 4 escrituras directas, TODAS del lado del estudio. La alumna reserva y
-- cancela SOLO por RPC, nunca por UPDATE/INSERT directo:
--   asistencia_screen.dart:196   estado='presente' + checked_in_at  (QR)
--   asistencia_screen.dart:561   estado='presente' + checked_in_at  (QR)
--   asistencia_screen.dart:1474  estado=<nuevo>    + checked_in_at  (manual)
--   estudio_admin_service.dart:600  estado='cancelada' (cancelarClase)
-- Por eso el trigger NO puede bloquear `estado` a secas: rompería el
-- escáner de QR. Distingue alumna (no toca nada) de estudio (estado +
-- checked_in_at).
--
-- Las 7 funciones que escriben reservas son todas owner=postgres y
-- SECURITY DEFINER, así que pasan por el guard de current_user:
--   apply_reservation, cancelar_mi_reserva, admin_cancel_reserva,
--   confirm_pre_reserva, estudio_cancelar_clase,
--   completar_reservas_vencidas, _waitlist_promote_interno
-- La edge `delete-account` escribe con service_role => también pasa.
--
-- Premisa del patrón, VERIFICADA en vivo (no asumida):
--   UPDATE directo del cliente      -> current_user = authenticated
--   dentro de una SECURITY DEFINER  -> current_user = postgres
--   owner de reservar_clase         -> postgres
-- =====================================================================


-- ---------------------------------------------------------------------
-- FIX 1: trigger de columnas (mismo molde que usuarios_bloquear_columnas_sensibles)
-- ---------------------------------------------------------------------
create or replace function public.reservas_bloquear_columnas_sensibles()
returns trigger language plpgsql set search_path to 'public' as $fn$
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

  return new;
end $fn$;

drop trigger if exists trg_reservas_columnas_sensibles on public.reservas;
create trigger trg_reservas_columnas_sensibles
before update on public.reservas
for each row execute function public.reservas_bloquear_columnas_sensibles();


-- ---------------------------------------------------------------------
-- FIX 2: cerrar el INSERT directo
-- ---------------------------------------------------------------------
-- Se borra en vez de dejarla inerte: nada en la app inserta directo y las
-- RPC son owner=postgres (no pasan por RLS). Dejarla sería una puerta que
-- el próximo que lea el código puede reabrir por error.
drop policy if exists "reservas_insert_own" on public.reservas;


-- ---------------------------------------------------------------------
-- Reversión (si hiciera falta)
-- ---------------------------------------------------------------------
-- drop trigger if exists trg_reservas_columnas_sensibles on public.reservas;
-- drop function if exists public.reservas_bloquear_columnas_sensibles();
-- create policy "reservas_insert_own" on public.reservas
--   for insert to public with check (auth.uid() = usuario_id);


-- =====================================================================
-- SUITE DE VERIFICACIÓN — 10 pruebas, con ROLLBACK, midiendo EFECTO
-- =====================================================================
-- No alcanza con "no tiró error": cada prueba mide el estado resultante.
-- Ajustá los 3 fixtures de arriba del bloque si cambian los datos.
-- Resultado esperado: 10/10 en `ok`.
--
-- Corrida del 2026-08-21 (post-aplicación, contra producción): 10/10.
--   1 revivir cancelada        -> bloqueado, estado sigue 'cancelada'
--   2 auto-presente            -> bloqueado, estado sigue 'cancelada'
--   3 inflar creditos_usados   -> bloqueado, sigue en 14
--   4 mudar de clase           -> bloqueado, sigue en clase 410
--   5 INSERT gratis            -> RLS lo rechaza, reservas sin cambio
--   6 reservar_clase           -> ok:true, créditos 100 -> 82 (-18)
--   7 cancelar_mi_reserva      -> ok:true, créditos 82 -> 100 (+18)
--   8 estudio marca presente   -> estado='presente'   (escáner QR intacto)
--   9 cancelarClase masivo     -> 1 fila actualizada  (intacto)
--  10 service_role escribe     -> 1 fila actualizada  (delete-account intacto)
-- =====================================================================
/*
begin;

-- Fixtures: ajustar a datos reales de la base.
--   alumna  = un usuario SIN rol admin y SIN fila en estudio_admins
--   estadm  = un usuario CON fila en estudio_admins del estudio de la clase
--   clase   = clase futura, con lugares y precio > 0
create temp table fx as select
  'd0d6d5a1-1c3b-4c3b-b97c-28c9404c62ee'::uuid as alumna,
  '4241f8db-d5f1-4f1a-85f6-8745a3cc791d'::uuid as estadm,
  410::bigint as clase, 18::int as precio;

create temp table r(n int, prueba text, esperado text, resultado text, efecto text, ok boolean);
grant all on r to authenticated, anon;

select public.grant_user_credits((select alumna from fx), 100, 'test_auditoria', null, 'fixture');
insert into public.reservas (usuario_id, clase_id, estado, creditos_usados, codigo_qr)
select alumna, clase, 'cancelada', 14, 'TESTQR000001' from fx;

do $outer$
declare
  j_alumna constant text := '{"sub":"d0d6d5a1-1c3b-4c3b-b97c-28c9404c62ee","role":"authenticated"}';
  j_estadm constant text := '{"sub":"4241f8db-d5f1-4f1a-85f6-8745a3cc791d","role":"authenticated"}';
  c_alumna uuid; c_clase bigint; c_precio int;
  v_est text; v_cu int; v_cl bigint; v_n int; v_res jsonb; v_cred int; v_qr text;
begin
  select alumna, clase, precio into c_alumna, c_clase, c_precio from fx;

  -- ATAQUE 1: revivir cancelada
  begin
    perform set_config('request.jwt.claims', j_alumna, true); set local role authenticated;
    update public.reservas set estado='confirmada' where codigo_qr='TESTQR000001';
    reset role; select estado into v_est from public.reservas where codigo_qr='TESTQR000001';
    insert into r values (1,'Revivir reserva cancelada','FALLAR','paso sin error','estado='||v_est,false);
  exception when others then reset role;
    select estado into v_est from public.reservas where codigo_qr='TESTQR000001';
    insert into r values (1,'Revivir reserva cancelada','FALLAR','bloqueado: '||SQLERRM,'estado sigue '||v_est, v_est='cancelada');
  end;

  -- ATAQUE 2: auto-marcarse presente
  begin
    perform set_config('request.jwt.claims', j_alumna, true); set local role authenticated;
    update public.reservas set estado='presente', checked_in_at=now() where codigo_qr='TESTQR000001';
    reset role; select estado into v_est from public.reservas where codigo_qr='TESTQR000001';
    insert into r values (2,'Alumna se marca PRESENTE','FALLAR','paso sin error','estado='||v_est,false);
  exception when others then reset role;
    select estado into v_est from public.reservas where codigo_qr='TESTQR000001';
    insert into r values (2,'Alumna se marca PRESENTE','FALLAR','bloqueado: '||SQLERRM,'estado sigue '||v_est, v_est='cancelada');
  end;

  -- ATAQUE 3: inflar creditos_usados
  begin
    perform set_config('request.jwt.claims', j_alumna, true); set local role authenticated;
    update public.reservas set creditos_usados=9999 where codigo_qr='TESTQR000001';
    reset role; select creditos_usados into v_cu from public.reservas where codigo_qr='TESTQR000001';
    insert into r values (3,'Inflar creditos_usados','FALLAR','paso sin error','creditos_usados='||v_cu,false);
  exception when others then reset role;
    select creditos_usados into v_cu from public.reservas where codigo_qr='TESTQR000001';
    insert into r values (3,'Inflar creditos_usados','FALLAR','bloqueado: '||SQLERRM,'creditos_usados sigue '||v_cu, v_cu=14);
  end;

  -- ATAQUE 4: mudarse a otra clase
  begin
    perform set_config('request.jwt.claims', j_alumna, true); set local role authenticated;
    update public.reservas set clase_id=(select id from public.clases where fecha>=now() order by creditos desc nulls last limit 1)
      where codigo_qr='TESTQR000001';
    reset role; select clase_id into v_cl from public.reservas where codigo_qr='TESTQR000001';
    insert into r values (4,'Mudar a la clase mas cara','FALLAR','paso sin error','clase_id='||v_cl,false);
  exception when others then reset role;
    select clase_id into v_cl from public.reservas where codigo_qr='TESTQR000001';
    insert into r values (4,'Mudar a la clase mas cara','FALLAR','bloqueado: '||SQLERRM,'clase_id sigue '||v_cl, v_cl=c_clase);
  end;

  -- ATAQUE 5: INSERT gratis
  begin
    select count(*) into v_n from public.reservas;
    perform set_config('request.jwt.claims', j_alumna, true); set local role authenticated;
    insert into public.reservas (usuario_id, clase_id, estado, creditos_usados, codigo_qr)
      values (c_alumna, c_clase, 'confirmada', 0, 'FRAUDE000001');
    reset role;
    insert into r values (5,'INSERT reserva confirmada con 0 creditos','FALLAR','paso sin error',
      'reservas '||v_n||' -> '||(select count(*) from public.reservas), false);
  exception when others then reset role;
    insert into r values (5,'INSERT reserva confirmada con 0 creditos','FALLAR','bloqueado: '||SQLERRM,
      'reservas siguen '||(select count(*) from public.reservas), (select count(*) from public.reservas)=v_n);
  end;

  -- LEGITIMO 6: reservar_clase (tiene que DESCONTAR creditos)
  begin
    select creditos into v_cred from public.usuarios where id=c_alumna;
    select count(*) into v_n from public.reservas;
    perform set_config('request.jwt.claims', j_alumna, true); set local role authenticated;
    v_res := public.reservar_clase(c_clase);
    reset role;
    insert into r values (6,'reservar_clase','ANDAR', coalesce(v_res::text,'null'),
      'reservas '||v_n||' -> '||(select count(*) from public.reservas)
      ||' | creditos '||coalesce(v_cred,-1)||' -> '||coalesce((select creditos from public.usuarios where id=c_alumna),-1),
      coalesce((v_res->>'ok')::boolean,false)
        and (select count(*) from public.reservas) = v_n+1
        and coalesce((select creditos from public.usuarios where id=c_alumna),-1) = coalesce(v_cred,0)-c_precio);
  exception when others then reset role;
    insert into r values (6,'reservar_clase','ANDAR','ROMPIO: '||SQLERRM,'',false);
  end;

  -- LEGITIMO 7: cancelar_mi_reserva (tiene que DEVOLVER creditos)
  begin
    select codigo_qr into v_qr from public.reservas where usuario_id=c_alumna and estado='confirmada' and clase_id=c_clase limit 1;
    select creditos into v_cred from public.usuarios where id=c_alumna;
    perform set_config('request.jwt.claims', j_alumna, true); set local role authenticated;
    v_res := public.cancelar_mi_reserva(v_qr);
    reset role;
    insert into r values (7,'cancelar_mi_reserva','ANDAR', coalesce(v_res::text,'null'),
      'creditos '||coalesce(v_cred,-1)||' -> '||coalesce((select creditos from public.usuarios where id=c_alumna),-1),
      coalesce((v_res->>'ok')::boolean,false)
        and coalesce((select creditos from public.usuarios where id=c_alumna),-1) = coalesce(v_cred,0)+c_precio);
  exception when others then reset role;
    insert into r values (7,'cancelar_mi_reserva','ANDAR','ROMPIO: '||SQLERRM,'',false);
  end;

  -- LEGITIMO 8: el ESTUDIO marca presente (escaner QR) — EL QUE NO HAY QUE ROMPER
  begin
    perform set_config('request.jwt.claims', j_estadm, true); set local role authenticated;
    update public.reservas set estado='presente', checked_in_at=now() where codigo_qr='TESTQR000001';
    reset role; select estado into v_est from public.reservas where codigo_qr='TESTQR000001';
    insert into r values (8,'ESTUDIO marca presente (escaner QR)','ANDAR','sin error','estado='||v_est, v_est='presente');
  exception when others then reset role;
    insert into r values (8,'ESTUDIO marca presente (escaner QR)','ANDAR','ROMPIO: '||SQLERRM,'',false);
  end;

  -- LEGITIMO 9: cancelarClase masivo del estudio — EL OTRO QUE NO HAY QUE ROMPER
  begin
    perform set_config('request.jwt.claims', j_estadm, true); set local role authenticated;
    update public.reservas set estado='cancelada' where clase_id=c_clase and estado<>'cancelada';
    get diagnostics v_n = ROW_COUNT;
    reset role;
    insert into r values (9,'ESTUDIO cancelarClase (UPDATE masivo)','ANDAR','sin error','filas actualizadas = '||v_n, v_n>=1);
  exception when others then reset role;
    insert into r values (9,'ESTUDIO cancelarClase (UPDATE masivo)','ANDAR','ROMPIO: '||SQLERRM,'',false);
  end;

  -- LEGITIMO 10: service_role (camino de delete-account)
  begin
    set local role service_role;
    update public.reservas set creditos_usados=7, estado='confirmada' where codigo_qr='TESTQR000001';
    get diagnostics v_n = ROW_COUNT;
    reset role;
    insert into r values (10,'service_role escribe reservas','ANDAR','sin error','filas actualizadas = '||v_n, v_n=1);
  exception when others then reset role;
    insert into r values (10,'service_role escribe reservas','ANDAR','ROMPIO: '||SQLERRM,'',false);
  end;
end $outer$;

select n, prueba, esperado, ok, resultado, efecto from r order by n;
select count(*) filter (where ok) || '/' || count(*) as resumen from r;

rollback;
*/

-- (fin)
