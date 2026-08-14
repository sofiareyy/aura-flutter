-- ============================================================================
-- AURA — Reservar la MISMA clase de Sculpt para la amiga
-- ============================================================================
-- Clase 926 · viernes 14/08 09:00 · 14 créditos
-- Amiga: amaliaburgos429@gmail.com
--
-- Corré primero el PASO 1. Si tiene cuenta y saldo, seguí con el PASO 2.

-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ PASO 1 — ¿Tiene cuenta y le alcanza?                                     │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Si devuelve 0 filas: no tiene cuenta, tiene que registrarse en la app.
-- Si `saldo` es menor a 14: hay que acreditarle créditos (ver PASO 1B).
select id,
       email,
       nombre,
       creditos as saldo,
       case
         when creditos >= 14 then '✅ le alcanza, seguí con el PASO 2'
         else '⚠️ le faltan ' || (14 - creditos) || ' créditos, mirá el PASO 1B'
       end as estado
  from public.usuarios
 where email = 'amaliaburgos429@gmail.com';


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ PASO 1B — Solo si NO tiene créditos suficientes                          │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Le acredita 14 créditos por el ledger (no a mano), con vencimiento a 60 días.
-- Quedan marcados como 'manual' para que después sepas que fue un regalo tuyo
-- y no una compra.
--
-- Descomentá y corré SOLO si el PASO 1 dijo que le faltan.
--
-- do $$
-- declare v_uid uuid;
-- begin
--   select id into v_uid from public.usuarios
--    where email = 'amaliaburgos429@gmail.com';
--   if v_uid is null then
--     raise exception 'No tiene cuenta todavía';
--   end if;
--   perform public.grant_user_credits(
--     v_uid, 14, 'manual',
--     to_char((current_date + 60), 'YYYY-MM-DD'),
--     'Créditos para grabación de video'
--   );
--   raise notice 'LISTO — 14 créditos acreditados';
-- end $$;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ PASO 2 — La reserva. Copiá y corré, no hay nada que completar.           │
-- └──────────────────────────────────────────────────────────────────────────┘

do $$
declare
  v_email     text   := 'amaliaburgos429@gmail.com';
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
    raise exception 'No existe un usuario con el mail % — tiene que registrarse primero', v_email;
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

  if v_creditos > 0 then
    v_consumido := public.consume_user_credits(v_uid, v_creditos);
    if not coalesce(v_consumido, false) then
      raise exception '% no tiene créditos suficientes (necesita %) — mirá el PASO 1B',
        v_email, v_creditos;
    end if;
  end if;

  v_qr := upper(substring(
    encode(digest(v_uid::text || '-' || v_clase_id::text || '-' || v_ahora::text,
                  'sha256'), 'hex')
    from 1 for 12));

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
-- │ PASO 3 — Las dos reservas juntas, para confirmar                         │
-- └──────────────────────────────────────────────────────────────────────────┘
select u.email, r.estado, r.creditos_usados, r.codigo_qr, c.fecha
  from public.reservas r
  join public.usuarios u on u.id = r.usuario_id
  join public.clases   c on c.id = r.clase_id
 where r.clase_id = 926
 order by r.created_at;

-- El cupo tiene que haber bajado de 5 a 3:
select lugares_total, lugares_disponibles as quedan
  from public.clases where id = 926;
