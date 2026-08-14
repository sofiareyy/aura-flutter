-- ============================================================================
-- AURA — Reservar Sculpt del 14/08 09:00 a nombre de tu hermana
-- ============================================================================
-- Clase elegida: id 926 · viernes 14/08 09:00 · cuesta 14 créditos · 5 lugares
-- Tu hermana tiene 40 créditos, así que le alcanza.
--
-- Si preferís OTRO horario, cambiá el 926 por el id que quieras de esta lista:
--     926 = 14/08 09:00      877 = 14/08 14:00      925 = 15/08 09:00
--     932 = 17/08 09:00      882 = 17/08 14:00      976 = 18/08 10:00
--
-- Esto NO inserta filas a mano: llama a las mismas funciones que usa la app
-- (consume_user_credits + apply_reservation), así que descuenta por el ledger,
-- baja el cupo y deja registrada la deuda al estudio.

-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ COPIÁ DESDE ACÁ Y CORRÉ. No hay nada que completar.                     │
-- └──────────────────────────────────────────────────────────────────────────┘

do $$
declare
  v_email     text   := 'julietarey2002@gmail.com';
  v_clase_id  bigint := 926;
  v_uid       uuid;
  v_clase     record;
  v_creditos  int;
  v_qr        text;
  v_ahora     timestamp := (now() at time zone 'America/Argentina/Buenos_Aires');
  v_consumido boolean;
  v_res       jsonb;
begin
  select id into v_uid from public.usuarios where email = lower(trim(v_email));
  if v_uid is null then
    raise exception 'No existe un usuario con el mail %', v_email;
  end if;

  select * into v_clase from public.clases where id = v_clase_id;
  if v_clase is null then
    raise exception 'No existe la clase %', v_clase_id;
  end if;

  if exists (
    select 1 from public.reservas
     where clase_id = v_clase_id
       and usuario_id = v_uid
       and estado in ('confirmada', 'presente', 'pre_confirmada')
  ) then
    raise exception '% ya tiene una reserva activa en esa clase', v_email;
  end if;

  if coalesce(v_clase.lugares_disponibles, 0) <= 0 then
    raise exception 'La clase ya no tiene lugares';
  end if;

  v_creditos := coalesce(v_clase.creditos, 0);

  -- 1) Descontar por el ledger.
  if v_creditos > 0 then
    v_consumido := public.consume_user_credits(v_uid, v_creditos);
    if not coalesce(v_consumido, false) then
      raise exception '% no tiene créditos suficientes (necesita %)',
        v_email, v_creditos;
    end if;
  end if;

  -- 2) QR con el mismo formato que genera la app.
  v_qr := upper(substring(
    encode(digest(v_uid::text || '-' || v_clase_id::text || '-' || v_ahora::text,
                  'sha256'), 'hex')
    from 1 for 12));

  -- 3) Crear la reserva y bajar el cupo.
  v_res := public.apply_reservation(v_uid, v_clase_id::integer, v_qr, v_creditos);

  if not coalesce((v_res ->> 'ok')::boolean, false) then
    if v_creditos > 0 then
      perform public.grant_user_credits(
        v_uid, v_creditos, 'rollback_reserva', null,
        'Devolucion por reserva manual fallida'
      );
    end if;
    raise exception 'apply_reservation falló: %', v_res ->> 'error';
  end if;

  raise notice 'LISTO — % reservó la clase %. Descontados % créditos. QR: %',
    v_email, v_clase_id, v_creditos, v_qr;
end $$;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ Y esto para confirmar que quedó bien                                     │
-- └──────────────────────────────────────────────────────────────────────────┘

-- La reserva, con su código QR:
select u.email, r.estado, r.creditos_usados, r.codigo_qr,
       c.nombre as clase, c.fecha
  from public.reservas r
  join public.usuarios u on u.id = r.usuario_id
  join public.clases   c on c.id = r.clase_id
 where r.created_at >= now() - interval '10 minutes'
 order by r.created_at desc;

-- El cupo bajó de 5 a 4, y el saldo de 40 a 26:
select c.lugares_disponibles as quedan_lugares
  from public.clases c where c.id = 926;

select email, creditos as saldo
  from public.usuarios where email = 'julietarey2002@gmail.com';
