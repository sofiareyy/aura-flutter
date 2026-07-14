import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const MP_PACKS_ACCESS_TOKEN = Deno.env.get('MP_PACKS_ACCESS_TOKEN')!

type PagoRow = {
  id: string
  user_id: string
  type: 'pack' | 'plan'
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

function validityForPack(packName: string | null, creditos: number) {
  const normalized = (packName ?? '').trim().toLowerCase()
  if (normalized === 'pack prueba' || creditos === 20) return 30
  return 60
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

    if (pago.type !== 'pack') {
      return json({ error: 'Solo se admiten packs de creditos.' }, 400)
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
    if (paymentRef['type'] && paymentRef['type'] !== 'pack') {
      return json({ error: 'El pago de Mercado Pago no corresponde a un pack' }, 400)
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

  const expiryStr = expirationDate(validityForPack(pago.pack_nombre, pago.creditos ?? 0))
  const { error } = await adminSupabase.rpc('process_approved_pack_payment', {
    p_pago_id: pago.id,
    p_mp_payment_id: String(payment.id),
    p_expires_at: expiryStr,
  })
  if (error) {
    console.error('confirmar-pago-manual: no se pudieron acreditar los creditos:', error.message)
    throw error
  }

  return 'approved'
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
