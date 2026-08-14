-- AURA — ¿Está la base lista para gift cards? (2026-08-07). Solo LEE.
-- La migración 20260724100000_gift_card_como_pack_pago.sql está sin commitear
-- en el repo; esto confirma si llegó a aplicarse en la base.

-- 1) Columnas del destinatario en `pagos`. Tienen que aparecer las dos.
select column_name, data_type
  from information_schema.columns
 where table_schema = 'public' and table_name = 'pagos'
   and column_name in ('gift_email', 'gift_mensaje');

-- 2) La tabla `regalos` y sus columnas.
select column_name, data_type, is_nullable
  from information_schema.columns
 where table_schema = 'public' and table_name = 'regalos'
 order by ordinal_position;

-- 3) ¿`process_approved_pack_payment` ya bifurca gift? Tiene que dar true.
select p.proname,
       p.prosrc ilike '%is_gift%'   as maneja_gift,
       p.prosrc ilike '%regalos%'   as inserta_regalo
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname = 'process_approved_pack_payment';

-- 4) ¿`pagos.type` admite 'gift'? Si hay un CHECK que solo permita
--    ('pack','plan'), el checkout de gift card falla al insertar.
select con.conname, pg_get_constraintdef(con.oid) as definicion
  from pg_constraint con
 where con.conrelid = 'public.pagos'::regclass
   and con.contype = 'c';

-- 5) Regalos ya existentes (si probaste antes).
select id, remitente_id, destinatario_email, creditos, codigo, usado, created_at
  from public.regalos
 order by created_at desc
 limit 20;
