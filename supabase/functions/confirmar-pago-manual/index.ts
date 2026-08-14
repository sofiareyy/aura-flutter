import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const MP_PACKS_ACCESS_TOKEN = Deno.env.get('MP_PACKS_ACCESS_TOKEN')!

type PagoRow = {
  id: string
  user_id: string
  type: 'pack' | 'plan' | 'gift'
  status: string
  creditos: number
  pack_nombre: string | null
  mp_preference_id: string | null
  mp_payment_id: string | null
  credits_granted_at: string | null
}

type MercadoPagoPayment = {
  id: string | number
  status?: string
  preference_id?: string | number | null
  external_reference?: string | null
}

function parseRef(ref: string): Record<string, string> {
  const params: Record<string, string> = {}
  for (const part of (ref ?? '').split('|')) {
    const idx = part.indexOf('=')
    if (idx !== -1) params[part.slice(0, idx)] = decodeURIComponent(part.slice(idx + 1))
  }
  return params
}

function expirationDate(validDays: number) {
  const expiry = new Date()
  expiry.setDate(expiry.getDate() + validDays)
  return expiry.toISOString().split('T')[0]
}

// Mismo criterio que packValidityDays en mp-webhook: primero el `vigencia`
// que crear-checkout-pack dejó en el external_reference (el vencimiento que
// se le prometió a la persona al comprar), y si no está, la tabla canónica.
//
// Antes esta función ignoraba el external_reference y usaba 30/60 fijos, así
// que un pack acreditado por acá podía vencer en otra fecha que el mismo pack
// acreditado por el webhook.
function validityForPack(
  params: Record<string, string>,
  packName: string | null,
  creditos: number,
) {
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

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const jwt = req.headers.get('x-aura-auth')?.trim() ?? ''
    if (!jwt) {
      return json({ error: 'Sin autorizacion' }, 401)
    }

    const userSupabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
    const adminSupabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)

    const {
      data: { user },
      error: authError,
    } = await userSupabase.auth.getUser(jwt)
    if (authError || !user) {
      return json({ error: 'No autorizado' }, 401)
    }

    const body = await req.json().catch(() => null)
    const pagoId = (body?.pago_id ?? '').toString().trim()
    const paymentId = (body?.payment_id ?? '').toString().trim()

    if (!pagoId && !paymentId) {
      return json({ error: 'Falta pago_id o payment_id' }, 400)
    }

    let payment: MercadoPagoPayment | null = null
    if (paymentId) {
      payment = await fetchMercadoPagoPayment(paymentId)
      if (!payment) {
        return json({ error: 'No se pudo verificar el pago en Mercado Pago' }, 502)
      }
    }

    let pago: PagoRow | null = null
    if (pagoId) {
      const { data } = await adminSupabase
        .from('pagos')
        .select('id, user_id, type, status, creditos, pack_nombre, mp_preference_id, mp_payment_id, credits_granted_at')
        .eq('id', pagoId)
        .maybeSingle<PagoRow>()
      pago = data
    } else if (payment) {
      pago = await findPagoForPayment(adminSupabase, payment)
    }

    if (!pago) {
      return json({ error: 'Pago no encontrado' }, 404)
    }

    if (pago.user_id != user.id) {
      return json({ error: 'No autorizado para este pago' }, 403)
    }

    if (pago.type !== 'pack' && pago.type !== 'gift') {
      return json({ error: 'Solo se admiten packs de creditos o gift cards.' }, 400)
    }

    if (pago.credits_granted_at != null) {
      return json({ status: 'approved' })
    }

    if (pago.status == 'approved') {
      return json({ error: 'Pago aprobado sin marca de acreditacion; requiere revision manual' }, 409)
    }

    if (!payment) {
      return json({ status: pago.status })
    }

    const paymentRef = parseRef(payment.external_reference ?? '')
    if (paymentRef['user_id'] && paymentRef['user_id'] !== user.id) {
      return json({ error: 'El pago de Mercado Pago corresponde a otro usuario' }, 403)
    }
    if (paymentRef['type'] && paymentRef['type'] !== 'pack' && paymentRef['type'] !== 'gift') {
      return json({ error: 'El pago de Mercado Pago no corresponde a un pack ni a una gift card' }, 400)
    }
    if (paymentRef['type'] && paymentRef['type'] !== pago.type) {
      return json({ error: 'El tipo del pago no coincide con la compra iniciada' }, 409)
    }
    if (paymentRef['pago_id'] && paymentRef['pago_id'] !== pago.id) {
      return json({ error: 'El pago no coincide con la compra iniciada' }, 409)
    }
    if (payment.preference_id && pago.mp_preference_id &&
        String(payment.preference_id) !== pago.mp_preference_id) {
      return json({ error: 'La preferencia no coincide con la compra iniciada' }, 409)
    }

    const status = await reconcilePack(adminSupabase, pago, payment)
    return json({ status })
  } catch (error) {
    console.error('confirmar-pago-manual excepcion:', error)
    return json({ error: 'Error interno del servidor' }, 500)
  }
})

async function reconcilePack(
  adminSupabase: ReturnType<typeof createClient>,
  pago: PagoRow,
  payment: MercadoPagoPayment,
) {
  const status: string = payment.status ?? pago.status

  if (status !== 'approved') {
    const { error } = await adminSupabase
      .from('pagos')
      .update({ status, mp_payment_id: String(payment.id) })
      .eq('id', pago.id)
    if (error) throw error
    return status
  }

  const refParams = parseRef(payment.external_reference ?? '')
  const expiryStr = expirationDate(
    validityForPack(refParams, pago.pack_nombre, pago.creditos ?? 0),
  )
  const { data: result, error } = await adminSupabase.rpc('process_approved_pack_payment', {
    p_pago_id: pago.id,
    p_mp_payment_id: String(payment.id),
    p_expires_at: expiryStr,
  })
  if (error) {
    console.error('confirmar-pago-manual: no se pudieron acreditar los creditos:', error.message)
    throw error
  }

  // Gift card: mandar el mail al destinatario solo en el primer procesamiento
  // (idempotente vía already_processed). Si el webhook ya lo procesó, este RPC
  // devuelve already_processed=true y no se manda un segundo mail.
  const r = result as Record<string, unknown> | null
  if (r && r.is_gift === true && r.already_processed === false && r.gift_codigo) {
    await sendGiftEmail(r)
  }

  return 'approved'
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
      console.error('confirmar-pago-manual: email-regalo falló:', await res.text())
    }
  } catch (e) {
    console.error('confirmar-pago-manual: excepción enviando email-regalo:', e)
  }
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

async function findPagoForPayment(
  adminSupabase: ReturnType<typeof createClient>,
  payment: MercadoPagoPayment,
): Promise<PagoRow | null> {
  const params = parseRef(payment.external_reference ?? '')
  const internalPagoId = params['pago_id'] ?? ''
  if (internalPagoId) {
    const { data } = await adminSupabase
      .from('pagos')
      .select('id, user_id, type, status, creditos, pack_nombre, mp_preference_id, mp_payment_id, credits_granted_at')
      .eq('id', internalPagoId)
      .maybeSingle<PagoRow>()
    if (data) return data
  }

  const { data: byPaymentId } = await adminSupabase
    .from('pagos')
    .select('id, user_id, type, status, creditos, pack_nombre, mp_preference_id, mp_payment_id, credits_granted_at')
    .eq('mp_payment_id', String(payment.id))
    .maybeSingle<PagoRow>()
  if (byPaymentId) return byPaymentId

  const preferenceId = payment.preference_id ? String(payment.preference_id) : ''
  if (!preferenceId) return null

  const { data } = await adminSupabase
    .from('pagos')
    .select('id, user_id, type, status, creditos, pack_nombre, mp_preference_id, mp_payment_id, credits_granted_at')
    .eq('mp_preference_id', preferenceId)
    .maybeSingle<PagoRow>()

  return data
}

async function fetchMercadoPagoPayment(paymentId: string): Promise<MercadoPagoPayment | null> {
  const response = await fetch(`https://api.mercadopago.com/v1/payments/${paymentId}`, {
    headers: { Authorization: `Bearer ${MP_PACKS_ACCESS_TOKEN}` },
  })

  if (!response.ok) return null
  return await response.json()
}
