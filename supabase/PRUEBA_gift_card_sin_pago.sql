-- ============================================================================
-- AURA — Prueba de gift card SIN pago real (2026-08-10)
-- ============================================================================
--
-- Simula un pago de gift card ya aprobado y corre el resto del flujo tal cual
-- lo haría Mercado Pago. Verifica todo menos la ida y vuelta a MP:
--   pago 'gift' aprobado -> se crea el regalo -> el destinatario lo canjea
--   -> le entran los créditos al ledger.
--
-- No toca plata ni credenciales de Mercado Pago. Al final hay un bloque de
-- limpieza para borrar lo que creó esta prueba.
--
-- CORRER POR PARTES, no todo de una: el PASO 3 se hace desde la app.

-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ ANTES DE EMPEZAR: elegí los dos usuarios de la prueba                    │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Necesitás dos cuentas que ya existan en la app: una que "compra" el regalo
-- y otra que lo recibe. Pueden ser tu cuenta de test y otra cualquiera.
select id, email, creditos
  from public.usuarios
 where email in ('test@aura.com', 'PONE_ACA_EL_MAIL_DEL_DESTINATARIO')
 order by email;
-- Anotá el `id` del comprador y el EMAIL del destinatario. Van en el PASO 1.


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ PASO 1 — Crear el pago de gift card, PENDIENTE                           │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Es exactamente lo que inserta crear-checkout-pack antes de mandarte a
-- Mercado Pago.
--
-- OJO CON EL STATUS: va 'pending', NO 'approved'.
--
-- process_approved_pack_payment es la que aprueba: al final hace
--     update pagos set status='approved', credits_granted_at=now()
-- Si el pago ya llega en 'approved' sin credits_granted_at, la función corta
-- con "Pago aprobado sin marca de acreditacion; requiere revision manual",
-- porque ese estado solo puede venir de alguien aprobando por afuera sin
-- acreditar. Es una protección real contra crear créditos de la nada.
--
-- Y tampoco pongas credits_granted_at a mano: la función lo lee como "esto ya
-- se procesó", devuelve already_processed=true y NO crea el regalo.

insert into public.pagos (
  user_id, type, status, amount, creditos, pack_nombre,
  gift_email, gift_mensaje
) values (
  'PONE_ACA_EL_UUID_DEL_COMPRADOR'::uuid,   -- ← del select de arriba
  'gift',
  'pending',                                 -- ← la función lo pasa a approved
  20000,                                     -- monto simbólico, no se cobra
  20,                                        -- créditos que va a recibir
  'Pack Prueba',
  'PONE_ACA_EL_MAIL_DEL_DESTINATARIO',       -- ← a quién va el regalo
  'Prueba de gift card, ignorar'
)
returning id as pago_id, type, status, creditos, gift_email;
-- 👉 Anotá el `pago_id` que devuelve. Va en el PASO 2.


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ PASO 2 — Procesar el pago (lo que hace el webhook de MP)                 │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Esta es la función real de producción, sin atajos. Si devuelve
-- is_gift=true y already_processed=false, el regalo quedó creado.

-- El mp_payment_id tiene que ser ÚNICO: la función rechaza uno ya vinculado a
-- otro pago. Si repetís la prueba, cambiá el número del final.
select public.process_approved_pack_payment(
  'PONE_ACA_EL_PAGO_ID'::uuid,               -- ← el que devolvió el PASO 1
  'TEST-SIN-MP-001',                         -- mp_payment_id simulado
  (current_date + interval '60 days')::text
) as resultado;

-- Y así queda el pago después: status 'approved' y credits_granted_at cargado.
-- Los puso la función, no vos.
select id, type, status, credits_granted_at, mp_payment_id, gift_email
  from public.pagos
 where id = 'PONE_ACA_EL_PAGO_ID'::uuid;

-- Verificar el regalo creado y quedarte con el CÓDIGO.
select id, remitente_id, destinatario_email, creditos, codigo, usado, mensaje,
       created_at
  from public.regalos
 order by created_at desc
 limit 3;
-- 👉 Anotá el `codigo` (formato GIFT-XXXXXXXX). Va en el PASO 3.

-- Correr el PASO 2 dos veces tiene que devolver already_processed=true y NO
-- crear un segundo regalo. Probalo: es la garantía de que un webhook repetido
-- no duplica el regalo ni manda dos mails.


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ PASO 3 — Canjear (ESTO VA DESDE LA APP, no acá)                          │
-- └──────────────────────────────────────────────────────────────────────────┘
-- canjear_regalo usa auth.uid() para saber quién canjea, y en el SQL editor
-- auth.uid() es null. Así que este paso se hace logueado:
--
--   1. Entrá a la app con la cuenta del DESTINATARIO
--   2. Perfil → "Canjear regalo"
--   3. Pegá el código GIFT-XXXXXXXX
--
-- Tiene que decir que se acreditaron los créditos.


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ PASO 4 — Verificar que los créditos llegaron a la persona correcta       │
-- └──────────────────────────────────────────────────────────────────────────┘
select u.email,
       u.creditos              as saldo_actual,
       m.source,
       m.amount_total          as creditos_acreditados,
       m.amount_remaining      as sin_usar,
       m.expires_at            as vence,
       m.meta ->> 'description' as detalle,
       m.created_at
  from public.creditos_movimientos m
  join public.usuarios u on u.id = m.user_id
 where m.source = 'regalo'
 order by m.created_at desc
 limit 10;
-- El movimiento tiene que estar a nombre del DESTINATARIO, no del comprador.
-- Y el regalo tiene que figurar usado = true:
select codigo, destinatario_email, usado from public.regalos
 order by created_at desc limit 3;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ LIMPIEZA — borrar lo que creó la prueba                                  │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Ojo: si ya canjeaste, los créditos quedaron acreditados de verdad. Para
-- dejarlo prolijo, descontáselos desde el backoffice (Admin → Usuarios →
-- ajustar créditos), que pasa por el ledger. NO edites usuarios.creditos a
-- mano: hay un trigger que lo bloquea.
--
-- delete from public.regalos where codigo = 'PONE_ACA_EL_CODIGO';
-- delete from public.pagos   where id     = 'PONE_ACA_EL_PAGO_ID'::uuid;
