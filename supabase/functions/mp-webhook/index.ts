// Recibe notificaciones de Mercado Pago para packs de créditos.
// Responde 200 inmediatamente y procesa en segundo plano.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const MP_PACKS_ACCESS_TOKEN =
  Deno.env.get('MP_PACKS_ACCESS_TOKEN') ?? Deno.env.get('MP_ACCESS_TOKEN')!
const MP_SUBSCRIPTIONS_ACCESS_TOKEN =
  Deno.env.get('MP_SUSCRIPCIONES_ACCESS_TOKEN') ??
  Deno.env.get('MP_SUBSCRIPTIONS_ACCESS_TOKEN') ??
  Deno.env.get('MP_ACCESS_TOKEN')!
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

function packValidityDays(params: Record<string, string>, packName: string, creditos: number) {
  const explicit = parseInt(params['vigencia'] ?? '0', 10)
  if (explicit > 0) return explicit

  const normalized = packName.trim().toLowerCase()
  if (normalized === 'pack prueba' || creditos === 20) return 60
  return 90
}

function expirationDate(validDays: number) {
  const expiry = new Date()
  expiry.setDate(expiry.getDate() + validDays)
  return expiry.toISOString().split('T')[0]
}

async function isValidSignature(req: Request, rawBody: string): Promise<boolean> {
  const secrets = [MP_WEBHOOK_SECRET, MP_PACKS_WEBHOOK_SECRET, MP_SUBSCRIPTIONS_WEBHOOK_SECRET]
    .filter((value): value is string => Boolean(value))

  if (secrets.length === 0) return true

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

async function procesarPago(paymentId: string) {
  const supabase = getAdmin()

  const mpRes = await fetch(`https://api.mercadopago.com/v1/payments/${paymentId}`, {
    headers: { Authorization: `Bearer ${MP_PACKS_ACCESS_TOKEN}` },
  })
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

  if (type !== 'pack' && type !== 'plan') {
    console.log('mp-webhook: notificación ignorada, tipo no soportado', { paymentId, type })
    return
  }

  if (!userId) {
    console.error('mp-webhook: user_id vacío en external_reference:', externalRef)
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

  if (type === 'pack') {
    const expiryStr = expirationDate(packValidityDays(params, packNombre, creditos))
    const { error: rpcErr } = await supabase.rpc('grant_user_credits', {
      p_user_id: userId,
      p_amount: creditos,
      p_source: 'pack',
      p_expires_at: expiryStr,
    })

    if (rpcErr) {
      console.warn('mp-webhook: grant_user_credits fallo (pack), usando fallback:', rpcErr.message)
      const { data: userRow } = await supabase
        .from('usuarios')
        .select('creditos')
        .eq('id', userId)
        .single()
      if (userRow) {
        await supabase
          .from('usuarios')
          .update({ creditos: (userRow.creditos ?? 0) + creditos, creditos_vencimiento: expiryStr })
          .eq('id', userId)
      }
    }

    console.log(`mp-webhook: acreditados ${creditos} créditos pack (${packNombre}) al usuario ${userId}`)
  } else if (type === 'plan') {
    // Suscripción mensual: otorgar créditos con vencimiento de 30 días
    const expiryStr = expirationDate(30)
    const { error: rpcErr } = await supabase.rpc('grant_user_credits', {
      p_user_id: userId,
      p_amount: creditos,
      p_source: 'plan',
      p_expires_at: expiryStr,
    })

    if (rpcErr) {
      console.warn('mp-webhook: grant_user_credits fallo (plan), usando fallback:', rpcErr.message)
      const { data: userRow } = await supabase
        .from('usuarios')
        .select('creditos')
        .eq('id', userId)
        .single()
      if (userRow) {
        await supabase
          .from('usuarios')
          .update({ creditos: (userRow.creditos ?? 0) + creditos, creditos_vencimiento: expiryStr })
          .eq('id', userId)
      }
    }

    // Actualizar estado del plan en el usuario
    const nextRenewal = new Date()
    nextRenewal.setDate(nextRenewal.getDate() + 30)
    await supabase
      .from('usuarios')
      .update({
        plan: planNombre || null,
        subscription_status: 'active',
        renewal_date: nextRenewal.toISOString().split('T')[0],
      })
      .eq('id', userId)

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
          await procesarPago(id)
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
          await procesarPago(dataId)
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
