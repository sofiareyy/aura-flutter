-- ============================================================================
-- AURA — PASO 2: limpiar datos de prueba + renombrar los planes
-- ============================================================================
-- Corré los bloques EN ORDEN. El 2A es de solo lectura.
--
-- ⚠️ NO corras el 2B hasta haber mirado el resultado del 2A.


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 2A — ⚠️ FRENO: la suscripción de Emma puede estar VIVA en Mercado Pago   │
-- └──────────────────────────────────────────────────────────────────────────┘
-- emma.raynner@gmail.com tiene mp_subscription_id = 75ec158a271845fe8f352b3cfed3efc7
-- Ese es un preapproval REAL en Mercado Pago, con un pago de plan asociado.
--
-- Borrar ese id de la base NO cancela nada en MP. Solo hace que pierdas la
-- única referencia para poder cancelarlo después. Si el preapproval quedó
-- autorizado, MP le sigue cobrando a esa tarjeta todos los meses y vos ya no
-- tenés cómo frenarlo desde la app.
--
-- ANTES de limpiar, entrá al panel de Mercado Pago (cuenta de SUSCRIPCIONES)
-- y buscá ese id. Si figura como authorized/pending, cancelalo ahí.
--
-- Esta consulta te muestra el pago asociado, para que sepas si llegó a cobrar:

select p.id,
       p.type,
       p.status,
       p.amount,
       p.creditos,
       p.mp_payment_id,
       p.mp_preapproval_id,
       p.credits_granted_at,
       u.email
  from public.pagos p
  join public.usuarios u on u.id = p.user_id
 where u.email = 'emma.raynner@gmail.com'
    or p.mp_preapproval_id = '75ec158a271845fe8f352b3cfed3efc7'
 order by p.created_at;

-- Si `credits_granted_at` está en null y `status` no es 'approved',
-- nunca se cobró y podés limpiar tranquila.


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 2B — Limpieza de las 4 cuentas de prueba                                 │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Deja todo en el estado "sin plan" real: plan en NULL (no el string
-- 'Sin plan'), subscription_status en 'none', sin fecha de renovación.
--
-- NO toca los créditos: test@aura.com se queda con sus 39 y tutiacotilla
-- con sus 5. Esos vinieron del ledger y borrarlos te descuadraría el saldo.

update public.usuarios
   set plan                = null,
       subscription_status = 'none',
       renewal_date        = null,
       mp_subscription_id  = null
 where email in (
   'clic@aura.com',
   'emma.raynner@gmail.com',
   'test@aura.com',
   'tutiacotilla@gmail.com'
 );

-- Verificación: tiene que devolver 0 filas.
select email, plan, subscription_status, mp_subscription_id, renewal_date
  from public.usuarios
 where plan is not null
    or coalesce(subscription_status, 'none') <> 'none'
    or mp_subscription_id is not null;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 2C — Los planes nuevos: Semanal / Frecuente / Libre                      │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Actualiza las 3 filas existentes por id (no borra ni inserta, así el
-- historial y las referencias por id siguen intactos).

update public.pricing_planes
   set nombre      = 'Semanal',
       creditos    = 70,
       precio      = 70000,
       descripcion = 'Para ir una vez por semana',
       destacado   = false,
       orden       = 1,
       activo      = true
 where id = 1;

update public.pricing_planes
   set nombre      = 'Frecuente',
       creditos    = 120,
       precio      = 108000,
       descripcion = 'Para entrenar seguido y variar de estudio',
       destacado   = true,
       orden       = 2,
       activo      = true
 where id = 2;

update public.pricing_planes
   set nombre      = 'Libre',
       creditos    = 160,
       precio      = 139200,
       descripcion = 'Para quienes no paran',
       destacado   = false,
       orden       = 3,
       activo      = true,
       -- Apuntaba a un plan viejo de MP con el precio anterior ($120.000).
       -- Nadie lo usa (el checkout arma el precio inline), pero si queda
       -- puede confundir más adelante.
       mp_plan_id  = null
 where id = 3;


-- Verificación final: los 3 planes nuevos, con el precio por crédito.
select orden,
       nombre,
       creditos,
       precio,
       round(precio::numeric / creditos, 0) as precio_por_credito,
       destacado,
       descripcion
  from public.pricing_planes
 where activo
 order by orden;

-- Tiene que dar:
--   1  Semanal    70  $70.000   $1.000/cr
--   2  Frecuente 120  $108.000    $900/cr   ← destacado
--   3  Libre     160  $139.200    $870/cr
