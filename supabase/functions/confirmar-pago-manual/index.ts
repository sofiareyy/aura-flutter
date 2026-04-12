import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const MP_PACKS_ACCESS_TOKEN =
  Deno.env.get('MP_PACKS_ACCESS_TOKEN') ?? Deno.env.get('MP_ACCESS_TOKEN')!

type PagoRow = {
  id: string
  user_id: string
  type: 'pack' | 'plan'
  status: string
  creditos: number
  pack_nombre: string | null
  mp_preference_id: string | null
  mp_payment_id: string | null
}

type MercadoPagoPayment = {
  id: string | number
  status?: string
  preference_id?: string | number | null
}

function expirationDate(validDays: number) {
  const expiry = new Date()
  expiry.setDate(expiry.getDate() + validDays)
  return expiry.toISOString().split('T')[0]
}

function validityForPack(packName: string | null, creditos: number) {
  const normalized = (packName ?? '').trim().toLowerCase()
  if (normalized === 'pack prueba' || creditos === 20) return 60
  return 90
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

    let pago: PagoRow | null = null
    if (pagoId) {
      const { data } = await adminSupabase
        .from('pagos')
        .select('id, user_id, type, status, creditos, pack_nombre, mp_preference_id, mp_payment_id')
        .eq('id', pagoId)
        .maybeSingle<PagoRow>()
      pago = data
    } else if (paymentId) {
      pago = await findPagoByPaymentId(adminSupabase, paymentId)
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

    if (pago.status == 'approved') {
      return json({ status: 'approved' })
    }

    const status = await reconcilePack(adminSupabase, pago, paymentId)
    return json({ status })
  } catch (error) {
    console.error('confirmar-pago-manual excepcion:', error)
    return json({ error: 'Error interno del servidor' }, 500)
  }
})

async function reconcilePack(
  adminSupabase: ReturnType<typeof createClient>,
  pago: PagoRow,
  paymentId: string,
) {
  if (!paymentId) return pago.status

  const mpRes = await fetch(`https://api.mercadopago.com/v1/payments/${paymentId}`, {
    headers: { Authorization: `Bearer ${MP_PACKS_ACCESS_TOKEN}` },
  })

  if (!mpRes.ok) {
    console.error('confirmar-pago-manual pack error:', await mpRes.text())
    return pago.status
  }

  const payment = await mpRes.json()
  const status: string = payment.status ?? pago.status

  await adminSupabase
    .from('pagos')
    .update({
      status,
      mp_payment_id: String(payment.id),
    })
    .eq('id', pago.id)

  if (status === 'approved' && pago.status !== 'approved') {
    const expiryStr = expirationDate(validityForPack(pago.pack_nombre, pago.creditos ?? 0))
    const { error: rpcErr } = await adminSupabase.rpc('grant_user_credits', {
      p_user_id: pago.user_id,
      p_amount: pago.creditos ?? 0,
      p_source: 'pack',
      p_expires_at: expiryStr,
    })

    if (rpcErr) {
      const { data: userRow } = await adminSupabase
        .from('usuarios')
        .select('creditos')
        .eq('id', pago.user_id)
        .single()

      await adminSupabase
        .from('usuarios')
        .update({
          creditos: (userRow?.creditos ?? 0) + (pago.creditos ?? 0),
          creditos_vencimiento: expiryStr,
        })
        .eq('id', pago.user_id)
    }
  }

  return status
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

async function findPagoByPaymentId(
  adminSupabase: ReturnType<typeof createClient>,
  paymentId: string,
): Promise<PagoRow | null> {
  const payment = await fetchMercadoPagoPayment(paymentId)
  if (!payment) return null

  const preferenceId = payment.preference_id ? String(payment.preference_id) : ''
  if (!preferenceId) return null

  const { data } = await adminSupabase
    .from('pagos')
    .select('id, user_id, type, status, creditos, pack_nombre, mp_preference_id, mp_payment_id')
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
