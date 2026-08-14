-- ============================================================================
-- AURA — pagos.type tiene que admitir 'gift' (2026-08-10)
-- ============================================================================
--
-- Bloqueante encontrado antes de probar gift cards: `pagos_type_check` solo
-- permitía ('plan', 'pack'). El flujo de regalo inserta type = 'gift', así que
-- la compra fallaba en el primer paso, antes de llegar a Mercado Pago.
--
-- Quién escribe 'gift' (siempre el servidor, nunca el cliente):
--   * crear-checkout-pack/index.ts -> insert into pagos (type: 'gift')
--   * mp-webhook/index.ts          -> insert de respaldo, mismo type
--
-- El cliente solo navega a /checkout con {'type':'gift', gift_email, ...} y es
-- la edge function la que inserta.
--
-- Los `status` que usa el flujo de gift son los mismos que los de pack
-- (pending / approved / cancelled), así que si existe un pagos_status_check no
-- hace falta tocarlo: los packs ya pasan por ahí. Igual lo listamos abajo para
-- confirmarlo con datos en vez de suponerlo.

begin;

-- ── El fix ──────────────────────────────────────────────────────────────────
-- Idempotente: drop if exists + add. Mantiene la semántica original (un NULL
-- sigue pasando el check, igual que antes) y solo suma 'gift'.
alter table public.pagos drop constraint if exists pagos_type_check;
alter table public.pagos
  add constraint pagos_type_check
  check (type in ('plan', 'pack', 'gift'));

commit;


-- ── VERIFICACIÓN (solo lee) ─────────────────────────────────────────────────

-- 1) El constraint nuevo. Tiene que incluir 'gift'.
select conname, pg_get_constraintdef(oid) as definicion
  from pg_constraint
 where conrelid = 'public.pagos'::regclass
   and conname = 'pagos_type_check';


-- ── LO QUE FALTA CONFIRMAR ANTES DE PROBAR ──────────────────────────────────
-- Estas consultas NO modifican nada. Son para descartar el resto de los
-- bloqueantes de una sola vez.

-- 2) TODOS los checks de pagos y regalos. Buscamos alguno que restrinja
--    valores que el flujo de gift vaya a escribir (status, creditos, etc.).
select cl.relname as tabla,
       con.conname,
       pg_get_constraintdef(con.oid) as definicion
  from pg_constraint con
  join pg_class cl on cl.oid = con.conrelid
  join pg_namespace n on n.oid = cl.relnamespace
 where n.nspname = 'public'
   and cl.relname in ('pagos', 'regalos')
   and con.contype in ('c', 'u')
 order by cl.relname, con.conname;

-- 3) Columnas NOT NULL sin default en las dos tablas. Si alguna no la completa
--    el flujo de gift, el insert falla igual que fallaba por el type.
--    En `pagos` el flujo escribe: user_id, type, status, amount, creditos,
--    pack_nombre, gift_email, gift_mensaje.
--    En `regalos` escribe: remitente_id, destinatario_email, creditos, codigo,
--    usado, mensaje.
select table_name, column_name, data_type, column_default
  from information_schema.columns
 where table_schema = 'public'
   and table_name in ('pagos', 'regalos')
   and is_nullable = 'NO'
   and column_default is null
 order by table_name, ordinal_position;

-- 4) ¿Están las columnas del destinatario en pagos? Sin estas dos, el
--    checkout de gift tampoco puede guardar a quién va dirigido.
select column_name, data_type
  from information_schema.columns
 where table_schema = 'public'
   and table_name = 'pagos'
   and column_name in ('gift_email', 'gift_mensaje');

-- 5) ¿process_approved_pack_payment ya bifurca gift? Tiene que dar true en
--    las dos columnas.
select p.proname,
       p.prosrc ilike '%is_gift%' as maneja_gift,
       p.prosrc ilike '%regalos%' as inserta_regalo
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname = 'process_approved_pack_payment';
