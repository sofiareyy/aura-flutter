-- AURA - Agregar la columna reservas.codigo_qr (2026-06-12).
--
-- Bug raiz del "QR invalido": el Dart code venia mandando codigo_qr en el
-- INSERT pero la columna nunca se creo en DB. PostgREST come el campo
-- desconocido (con Prefer: return=representation devuelve el resto). El
-- resultado: la reserva queda en DB pero sin codigo_qr -> ningun scan
-- la encuentra por .eq('codigo_qr', ...).
--
-- Las reservas previas a este parche van a recibir un codigo_qr NUEVO
-- en el backfill, distinto al QR que el usuario tenga rendereado en
-- pantalla. Esos QRs viejos no van a matchear nunca; el estudio debera
-- marcarlas presente manualmente o que el alumno cancele y vuelva a
-- reservar. Las reservas nuevas (post-parche) andan normales.


-- 1. Columna ---------------------------------------------------------------

alter table public.reservas
  add column if not exists codigo_qr text;


-- 2. Backfill -------------------------------------------------------------
-- Formato igual al de _generarCodigoQr en lib/services/reservas_service.dart:
--   AURA-<8 primeros chars del usuario_id en mayusculas>-<clase_id>-
--        <created_at epoch ms>-<random 4 digitos>
-- Solo tocamos filas que tengan codigo_qr NULL para no pisar nada.

update public.reservas
   set codigo_qr =
       'AURA-' ||
       upper(substring(usuario_id::text from 1 for 8)) || '-' ||
       clase_id::text || '-' ||
       (extract(epoch from created_at) * 1000)::bigint::text || '-' ||
       lpad((floor(random() * 10000))::int::text, 4, '0')
 where codigo_qr is null;


-- 3. Indice unico ---------------------------------------------------------
-- Defiende contra colisiones improbables del backfill o futuras
-- duplicaciones por bug en el generador. Idempotente.

create unique index if not exists reservas_codigo_qr_key
  on public.reservas (codigo_qr);


-- 4. Verificacion ---------------------------------------------------------

select column_name, data_type, is_nullable
  from information_schema.columns
 where table_schema = 'public'
   and table_name   = 'reservas'
   and column_name  = 'codigo_qr';

select codigo_qr, estado, clase_id, usuario_id, created_at
  from public.reservas
 order by created_at desc
 limit 5;
