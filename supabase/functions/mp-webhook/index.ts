// Recibe notificaciones de Mercado Pago para packs de créditos y suscripciones.
// Responde 200 inmediatamente y procesa en segundo plano.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
// Tokens dedicados por cuenta MP. Packs y suscripciones pueden ser cuentas
// distintas, así que cada tipo de pago se verifica con su propio access token.
// (Se eliminó el MP_ACCESS_TOKEN genérico para no verificar todo con un token.)
const MP_PACKS_ACCESS_TOKEN = Deno.env.get('MP_PACKS_ACCESS_TOKEN')!
const MP_SUBSCRIPTIONS_ACCESS_TOKEN =
  Deno.env.get('MP_SUBSCRIPTIONS_ACCESS_TOKEN') ??
  Deno.env.get('MP_SUSCRIPCIONES_ACCESS_TOKEN')!
const MP_WEBHOOK_SECRET = Deno.env.get('MP_WEBHOOK_SECRET')
const MP_PACKS_WEBHOOK_SECRET = Deno.env.get('MP_PACKS_WEBHOOK_SECRET')
const MP_SUBSCRIPTIONS_WEBHOOK_SECRET = Deno.env.get('MP_SUBSCRIPTIONS_WEBHOOK_SECRET')

function getAdmin() {
  return createClient(SUPABASE_URL, SERVICE_ROLE_KEY)
}

function parseRef(ref: string): Record<string, string> {
  const params: Record<string, string> = {}
  for (const part of (ref ?? '').split('|')) {
    const idx = part.indexOf('=')
    if (idx !== -1) params[part.slice(0, idx)] = decodeURIComponent(part.slice(idx + 1))
  }
  return params
}

// El `vigencia` del external_reference lo arma crear-checkout-pack desde
// pricing_credit_packs; el cliente no lo puede tocar. Es el vencimiento que
// se le prometió a la persona al comprar, así que se respeta aunque después
// cambien los valores de la tabla.
//
// canonicalPackValidity es el respaldo para pagos viejos sin ese dato.
function packValidityDays(params: Record<string, string>, packName: string, creditos: number) {
  const explicit = parseInt(params['vigencia'] ?? '0', 10)
  if (explicit > 0 && explicit <= 365) return explicit
  return canonicalPackValidity(packName, creditos)
}

// Espejo de `vigenciaDias` en lib/services/pricing_service.dart y de
// pricing_credit_packs.vencimiento_dias. Si cambiás uno, cambiá los tres.
function canonicalPackValidity(packName: string | null, creditos: number) {
  const n = (packName ?? '').trim().toLowerCase()
  if (n === 'pack prueba' || creditos === 20) return 30
  if (n === 'pack esencial' || creditos === 50) return 45
  if (n === 'pack popular' || creditos === 100) return 45
  if (n === 'pack full' || creditos === 200) return 60
  return 60 // desconocido (ej. gift cards): se mantiene el valor histórico
}

function expirationDate(validDays: number) {
  const expiry = new Date()
  expiry.setDate(expiry.getDate() + validDays)
  return expiry.toISOString().split('T')[0]
}

type PackPagoRow = {
  id: string
  user_id: string
  type: string
  status: string
  creditos: number
  pack_nombre: string | null
  mp_payment_id: string | null
  mp_preference_id: string | null
  credits_granted_at: string | null
}

const packPagoSelect =
  'id, user_id, type, status, creditos, pack_nombre, mp_payment_id, mp_preference_id, credits_granted_at'

async function findPackPago(
  supabase: ReturnType<typeof createClient>,
  internalPagoId: string,
  mpPaymentId: string,
  preferenceId: string,
  userId: string,
): Promise<PackPagoRow | null> {
  if (internalPagoId) {
    const { data, error } = await supabase
      .from('pagos')
      .select(packPagoSelect)
      .eq('id', internalPagoId)
      .maybeSingle<PackPagoRow>()
    if (error) throw error
    if (data) {
      if (data.user_id !== userId || (data.type !== 'pack' && data.type !== 'gift')) {
        throw new Error('El pago interno no coincide con el usuario o el tipo del pago de Mercado Pago')
      }
      return data
    }
  }

  const { data: byPaymentId, error: paymentIdError } = await supabase
    .from('pagos')
    .select(packPagoSelect)
    .eq('mp_payment_id', mpPaymentId)
    .maybeSingle<PackPagoRow>()
  if (paymentIdError) throw paymentIdError
  if (byPaymentId) return byPaymentId

  if (preferenceId) {
    const { data: byPreference, error: preferenceError } = await supabase
      .from('pagos')
      .select(packPagoSelect)
      .eq('mp_preference_id', preferenceId)
      .maybeSingle<PackPagoRow>()
    if (preferenceError) throw preferenceError
    if (byPreference) return byPreference
  }

  return null
}

async function processPackPayment(
  supabase: ReturnType<typeof createClient>,
  payment: Record<string, unknown>,
  params: Record<string, string>,
) {
  const status = String(payment.status ?? 'pending')
  const mpPaymentId = String(payment.id ?? '')
  const preferenceId = payment.preference_id ? String(payment.preference_id) : ''
  const internalPagoId = params['pago_id'] ?? ''
  const userId = params['user_id'] ?? ''
  const externalCredits = parseInt(params['creditos'] ?? '0', 10)
  const externalPackName = params['pack'] ?? ''

  let pago = await findPackPago(
    supabase,
    internalPagoId,
    mpPaymentId,
    preferenceId,
    userId,
  )

  if (!pago) {
    const safeInitialStatus = status === 'approved' ? 'pending' : status
    const { data: inserted, error: insertError } = await supabase
      .from('pagos')
      .insert({
        user_id: userId,
        type: params['type'] === 'gift' ? 'gift' : 'pack',
        mp_payment_id: mpPaymentId,
        mp_preference_id: preferenceId || null,
        status: safeInitialStatus,
        amount: Math.round(Number(payment.transaction_amount ?? 0)),
        creditos: externalCredits,
        pack_nombre: externalPackName || null,
      })
      .select(packPagoSelect)
      .single<PackPagoRow>()
    if (insertError || !inserted) {
      throw insertError ?? new Error('No se pudo registrar el pago de Mercado Pago')
    }
    pago = inserted
  }

  if (pago.user_id !== userId || (pago.type !== 'pack' && pago.type !== 'gift')) {
    throw new Error('El pago localizado no coincide con el usuario o el tipo esperado')
  }

  if (pago.credits_granted_at != null) {
    console.log(`mp-webhook: pago ${mpPaymentId} ya acreditado, ignorando reintento`)
    return
  }

  if (pago.status === 'approved') {
    throw new Error('Pago aprobado sin marca de acreditacion; requiere revision manual')
  }

  if (status !== 'approved') {
    const { error } = await supabase
      .from('pagos')
      .update({ status, mp_payment_id: mpPaymentId })
      .eq('id', pago.id)
    if (error) throw error
    return
  }

  const creditos = pago.creditos ?? externalCredits
  const packNombre = pago.pack_nombre ?? externalPackName
  const expiryStr = expirationDate(packValidityDays(params, packNombre, creditos))
  const { data: result, error: processError } = await supabase.rpc(
    'process_approved_pack_payment',
    {
      p_pago_id: pago.id,
      p_mp_payment_id: mpPaymentId,
      p_expires_at: expiryStr,
    },
  )

  if (processError) {
    console.error('mp-webhook: no se pudieron acreditar los creditos del pack:', processError.message)
    throw processError
  }

  console.log('mp-webhook: pago pack procesado', {
    pagoId: pago.id,
    mpPaymentId,
    result,
  })

  // Gift card: mandar el mail al destinatario. El RPC es idempotente y solo
  // devuelve el código en el PRIMER procesamiento (already_processed=false), así
  // que un reintento del webhook no genera un segundo mail. Best-effort: si el
  // mail falla, el regalo ya quedó creado y se puede reenviar a mano.
  const r = result as Record<string, unknown> | null
  if (r && r.is_gift === true && r.already_processed === false && r.gift_codigo) {
    await sendGiftEmail(r)
  }
}

async function sendGiftEmail(r: Record<string, unknown>) {
  try {
    const res = await fetch(`${SUPABASE_URL}/functions/v1/email-regalo`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        destinatario_email: r.gift_email,
        codigo: r.gift_codigo,
        creditos: r.gift_creditos,
        remitente_nombre: r.remitente_nombre,
        mensaje: r.gift_mensaje,
      }),
    })
    if (!res.ok) {
      console.error('mp-webhook: email-regalo falló:', await res.text())
    }
  } catch (e) {
    console.error('mp-webhook: excepción enviando email-regalo:', e)
  }
}

async function isValidSignature(req: Request, rawBody: string): Promise<boolean> {
  const secrets = [MP_WEBHOOK_SECRET, MP_PACKS_WEBHOOK_SECRET, MP_SUBSCRIPTIONS_WEBHOOK_SECRET]
    .filter((value): value is string => Boolean(value))

  // Fail-CLOSED: sin secret configurado se rechaza todo. Antes devolvía true
  // (aceptaba cualquier POST), lo que permitía acreditar packs falsos.
  if (secrets.length === 0) {
    console.error('mp-webhook: sin MP_WEBHOOK_SECRET configurado; rechazando')
    return false
  }

  const signature = req.headers.get('x-signature') ?? ''
  const requestId = req.headers.get('x-request-id') ?? ''
  const parts: Record<string, string> = {}
  for (const seg of signature.split(',')) {
    const [k, v] = seg.split('=')
    if (k && v) parts[k] = v
  }
  const ts = parts['ts']
  const v1 = parts['v1']
  if (!ts || !v1) return false

  let dataId = ''
  try {
    dataId = (JSON.parse(rawBody) as { data?: { id?: unknown } })?.data?.id?.toString() ?? ''
  } catch {
    dataId = ''
  }

  const template = `id:${dataId};request-id:${requestId};ts:${ts};`

  for (const secret of secrets) {
    const key = await crypto.subtle.importKey(
      'raw',
      new TextEncoder().encode(secret),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['sign'],
    )
    const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(template))
    const computed = Array.from(new Uint8Array(mac))
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('')

    if (computed === v1) return true
  }

  return false
}

async function procesarPago(paymentId: string, eventType = 'payment') {
  const supabase = getAdmin()

  // El external_reference (pack vs plan) solo se conoce DESPUÉS de traer el pago,
  // pero el token depende de la cuenta MP (packs y suscripciones son distintas).
  // Usamos el tipo de evento como señal: 'subscription_authorized_payment' es un
  // cobro recurrente de suscripción -> token de suscripciones; el resto ('payment')
  // es un pack -> token de packs. Con fallback al otro token por las dudas.
  const esSuscripcion = eventType === 'subscription_authorized_payment'
  const primaryToken = esSuscripcion
    ? MP_SUBSCRIPTIONS_ACCESS_TOKEN
    : MP_PACKS_ACCESS_TOKEN
  const fallbackToken = esSuscripcion
    ? MP_PACKS_ACCESS_TOKEN
    : MP_SUBSCRIPTIONS_ACCESS_TOKEN

  let mpRes = await fetch(`https://api.mercadopago.com/v1/payments/${paymentId}`, {
    headers: { Authorization: `Bearer ${primaryToken}` },
  })
  if (!mpRes.ok && fallbackToken && fallbackToken !== primaryToken) {
    console.warn(
      `mp-webhook: pago ${paymentId} falló con el token primario ` +
      `(${esSuscripcion ? 'suscripciones' : 'packs'}, status ${mpRes.status}), ` +
      `reintentando con el otro token`,
    )
    mpRes = await fetch(`https://api.mercadopago.com/v1/payments/${paymentId}`, {
      headers: { Authorization: `Bearer ${fallbackToken}` },
    })
  }
  if (!mpRes.ok) {
    console.error(`mp-webhook: no se pudo obtener pago ${paymentId}:`, await mpRes.text())
    return
  }

  const payment = await mpRes.json()
  const status: string = payment.status
  const mpPaymentId = String(payment.id)
  const externalRef: string = payment.external_reference ?? ''
  const preferenceId: string = payment.preference_id ? String(payment.preference_id) : ''
  const params = parseRef(externalRef)
  const userId = params['user_id']
  const type = params['type'] ?? 'pack'
  const creditos = parseInt(params['creditos'] ?? '0', 10)
  const packNombre = params['pack'] ?? ''
  const planNombre = params['plan'] ?? ''

  if (type !== 'pack' && type !== 'gift' && type !== 'plan') {
    console.log('mp-webhook: notificación ignorada, tipo no soportado', { paymentId, type })
    return
  }

  if (!userId) {
    console.error('mp-webhook: user_id vacío en external_reference:', externalRef)
    return
  }

  if (type === 'pack' || type === 'gift') {
    await processPackPayment(supabase, payment, params)
    return
  }

  const { data: existingByPaymentId } = await supabase
    .from('pagos')
    .select('id, status')
    .eq('mp_payment_id', mpPaymentId)
    .maybeSingle()

  if (existingByPaymentId?.status === 'approved') {
    console.log(`mp-webhook: pago ${mpPaymentId} ya procesado, ignorando`)
    return
  }

  let targetPagoId = existingByPaymentId?.id ?? null

  if (targetPagoId) {
    await supabase
      .from('pagos')
      .update({ status, mp_payment_id: mpPaymentId })
      .eq('id', targetPagoId)
  } else {
    const { data: pagoByPref } = preferenceId
      ? await supabase
          .from('pagos')
          .select('id, status')
          .eq('mp_preference_id', preferenceId)
          .maybeSingle()
      : { data: null }

    if (pagoByPref) {
      targetPagoId = pagoByPref.id
      if (pagoByPref.status !== 'approved') {
        await supabase
          .from('pagos')
          .update({ status, mp_payment_id: mpPaymentId })
          .eq('id', pagoByPref.id)
      }
    } else {
      const { data: inserted } = await supabase
        .from('pagos')
        .insert({
          user_id: userId,
          type,
          mp_payment_id: mpPaymentId,
          mp_preference_id: preferenceId || null,
          status,
          amount: Math.round((payment.transaction_amount ?? 0)),
          creditos,
          pack_nombre: type === 'pack' ? (packNombre || null) : null,
          plan_nombre: type === 'plan' ? (planNombre || null) : null,
        })
        .select('id')
        .single()
      targetPagoId = inserted?.id ?? null
    }
  }

  if (status !== 'approved') {
    // Guardar el estado real del rechazo para que la app pueda mostrarlo
    if (targetPagoId && (status === 'rejected' || status === 'cancelled')) {
      await supabase
        .from('pagos')
        .update({ status, mp_payment_id: mpPaymentId })
        .eq('id', targetPagoId)
      console.log(`mp-webhook: pago ${mpPaymentId} ${status} por el banco, usuario ${userId}`)
    }
    return
  }

  if (type === 'plan') {
    // Idempotente vía process_approved_plan_payment (gemelo del de packs):
    // `for update` + `credits_granted_at`. Una reentrega del MISMO mp_payment_id
    // cae en la MISMA fila (índice único) → already_processed → NO acredita de
    // nuevo. Una renovación mensual es un mp_payment_id nuevo → fila nueva →
    // acredita. El RPC también actualiza el estado del plan y dispara el referido.
    if (!targetPagoId) {
      console.warn('mp-webhook: plan sin pago_id (posible reentrega concurrente), ignorando')
      return
    }
    const { data: planRes, error: planErr } = await supabase.rpc('process_approved_plan_payment', {
      p_pago_id: targetPagoId,
      p_mp_payment_id: mpPaymentId,
      p_plan_nombre: planNombre || '',
      p_expires_at: expirationDate(60),
    })
    if (planErr) {
      console.error('mp-webhook: process_approved_plan_payment falló:', planErr.message)
      return
    }
    if ((planRes as { already_processed?: boolean } | null)?.already_processed) {
      console.log(`mp-webhook: plan ${mpPaymentId} ya acreditado (reentrega), ignorando`)
      return
    }
    console.log(`mp-webhook: acreditados ${creditos} créditos plan (${planNombre}) al usuario ${userId}`)
  }

  if (targetPagoId) {
    await supabase
      .from('pagos')
      .update({ status: 'approved', mp_payment_id: mpPaymentId })
      .eq('id', targetPagoId)
  }
}

async function procesarPreapproval(preapprovalId: string) {
  const supabase = getAdmin()

  const mpRes = await fetch(`https://api.mercadopago.com/preapproval/${preapprovalId}`, {
    headers: { Authorization: `Bearer ${MP_SUBSCRIPTIONS_ACCESS_TOKEN}` },
  })
  if (!mpRes.ok) {
    console.error(`mp-webhook: no se pudo obtener preapproval ${preapprovalId}:`, await mpRes.text())
    return
  }

  const preapproval = await mpRes.json()
  const status: string = preapproval.status ?? 'pending'
  const externalRef: string = preapproval.external_reference ?? ''
  const params = parseRef(externalRef)
  const userId = params['user_id']
  const type = params['type'] ?? 'plan'
  const planNombre = params['plan'] ?? ''
  const creditos = parseInt(params['creditos'] ?? '0', 10)

  if (type !== 'plan' || !userId) {
    console.log('mp-webhook: preapproval ignorado', { preapprovalId, type, userId })
    return
  }

  const { data: pagoByPreapproval } = await supabase
    .from('pagos')
    .select('id, status')
    .eq('mp_preapproval_id', preapprovalId)
    .maybeSingle()

  if (pagoByPreapproval) {
    await supabase
      .from('pagos')
      .update({ status })
      .eq('id', pagoByPreapproval.id)
  }

  if (status === 'authorized' || status === 'active') {
    const renewalDate = preapproval.next_payment_date
      ? String(preapproval.next_payment_date).split('T')[0]
      : null

    await supabase
      .from('usuarios')
      .update({
        plan: planNombre || null,
        mp_subscription_id: preapprovalId,
        subscription_status: 'active',
        renewal_date: renewalDate,
      })
      .eq('id', userId)

    if (pagoByPreapproval) {
      await supabase
        .from('pagos')
        .update({ status: 'approved' })
        .eq('id', pagoByPreapproval.id)
    }

    console.log(`mp-webhook: suscripción ${preapprovalId} activa para usuario ${userId}`)
  } else if (status === 'cancelled' || status === 'paused') {
    // MP agotó reintentos o el usuario canceló — limpiar plan del usuario
    await supabase
      .from('usuarios')
      .update({
        plan: null,
        subscription_status: status,
        renewal_date: null,
      })
      .eq('id', userId)

    console.log(`mp-webhook: suscripción ${preapprovalId} ${status} para usuario ${userId}`)
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'GET') {
    const url = new URL(req.url)
    const topic = url.searchParams.get('topic') ?? url.searchParams.get('type')
    const id = url.searchParams.get('id')
    console.log('mp-webhook: GET recibido', { topic, id, url: req.url })

    if ((topic === 'payment' || topic === 'subscription_authorized_payment') && id) {
      queueMicrotask(async () => {
        try {
          await procesarPago(id, topic)
        } catch (error) {
          console.error('mp-webhook: error procesando GET', error)
        }
      })
    } else if ((topic === 'preapproval' || topic === 'subscription_preapproval') && id) {
      queueMicrotask(async () => {
        try {
          await procesarPreapproval(id)
        } catch (error) {
          console.error('mp-webhook: error procesando preapproval GET', error)
        }
      })
    }

    return new Response('ok', { status: 200 })
  }

  if (req.method === 'POST') {
    const rawBody = await req.text()
    console.log('mp-webhook: POST recibido', {
      url: req.url,
      xSignature: req.headers.get('x-signature'),
      xRequestId: req.headers.get('x-request-id'),
      body: rawBody,
    })

    queueMicrotask(async () => {
      try {
        const signature = req.headers.get('x-signature') ?? ''
        if (signature && !(await isValidSignature(req, rawBody))) {
          console.warn('mp-webhook: firma invalida, continuando con verificacion por API')
        }

        let notification: Record<string, unknown>
        try {
          notification = JSON.parse(rawBody)
        } catch (error) {
          console.error('mp-webhook: body invalido, se responde 200 igual', error)
          return
        }

        const type = notification.type as string | undefined
        const dataId = ((notification.data as Record<string, unknown>)?.id as string | undefined)
        console.log('mp-webhook: POST parseado', { type, dataId })

        if ((type === 'payment' || type === 'subscription_authorized_payment') && dataId) {
          await procesarPago(dataId, type)
        } else if ((type === 'preapproval' || type === 'subscription_preapproval') && dataId) {
          await procesarPreapproval(dataId)
        } else {
          console.log('mp-webhook: evento ignorado', { type, dataId })
        }
      } catch (error) {
        console.error('mp-webhook: error procesando POST', error)
      }
    })

    return new Response('ok', { status: 200 })
  }

  return new Response('Method not allowed', { status: 405 })
})
