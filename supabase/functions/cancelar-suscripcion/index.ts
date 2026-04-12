import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const jwt = req.headers.get('x-aura-auth')?.trim() ?? ''
    if (!jwt) return json({ error: 'Sin autorización' }, 401)

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const userSupabase = createClient(
      supabaseUrl,
      Deno.env.get('SUPABASE_ANON_KEY')!,
    )
    const adminSupabase = createClient(
      supabaseUrl,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const { data: { user }, error: authError } = await userSupabase.auth.getUser(jwt)
    if (authError || !user) {
      return json({ error: 'No autorizado' }, 401)
    }

    const { data: usuario } = await adminSupabase
      .from('usuarios')
      .select('mp_subscription_id')
      .eq('id', user.id)
      .maybeSingle()

    const subscriptionId = usuario?.mp_subscription_id?.toString()
    if (!subscriptionId) {
      return json({ error: 'No encontramos una suscripción activa para cancelar.' }, 400)
    }

    const mpToken =
      Deno.env.get('MP_SUBSCRIPTIONS_ACCESS_TOKEN') ??
      Deno.env.get('MP_ACCESS_TOKEN')!

    const mpRes = await fetch(`https://api.mercadopago.com/preapproval/${subscriptionId}`, {
      method: 'PUT',
      headers: {
        Authorization: `Bearer ${mpToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ status: 'cancelled' }),
    })

    if (!mpRes.ok) {
      const errText = await mpRes.text()
      console.error('cancelar-suscripcion MP error:', errText)
      return json({ error: 'No se pudo cancelar la suscripción en Mercado Pago.' }, 500)
    }

    await adminSupabase
      .from('usuarios')
      .update({
        subscription_status: 'cancelled',
      })
      .eq('id', user.id)

    return json({ ok: true })
  } catch (e) {
    console.error('cancelar-suscripcion excepción:', e)
    return json({ error: 'Error interno del servidor' }, 500)
  }
})

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
