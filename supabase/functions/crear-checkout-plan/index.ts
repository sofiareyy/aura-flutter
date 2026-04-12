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

    const body = await req.json().catch(() => null)
    const { plan_nombre, plan_creditos, plan_precio } = body ?? {}

    if (!plan_nombre || typeof plan_creditos !== 'number' || typeof plan_precio !== 'number') {
      return json({ error: 'Faltan campos: plan_nombre, plan_creditos, plan_precio' }, 400)
    }

    const payerEmail = user.email ?? ''
    if (!payerEmail) {
      return json({ error: 'No encontramos un email válido para la suscripción.' }, 400)
    }

    const { data: pago, error: pagoErr } = await adminSupabase
      .from('pagos')
      .insert({
        user_id: user.id,
        type: 'plan',
        status: 'pending',
        amount: plan_precio,
        creditos: plan_creditos,
        plan_nombre,
      })
      .select('id')
      .single()

    if (pagoErr || !pago?.id) {
      console.error('Error insertando pago plan antes de checkout:', pagoErr?.message)
      return json({ error: 'No se pudo preparar la suscripción.' }, 500)
    }

    const mpToken =
      Deno.env.get('MP_SUBSCRIPTIONS_ACCESS_TOKEN') ??
      Deno.env.get('MP_ACCESS_TOKEN')!
    const configuredBaseUrl = Deno.env.get('APP_BASE_URL')?.trim() ?? ''
    const requestOrigin = req.headers.get('origin')?.trim() ?? ''
    const requestReferer = req.headers.get('referer')?.trim() ?? ''
    const refererOrigin = requestReferer ? new URL(requestReferer).origin : ''
    const fallbackBaseUrl = requestOrigin || refererOrigin || 'http://localhost:3000'
    const appBaseUrl = ((configuredBaseUrl && !configuredBaseUrl.includes('example.com'))
      ? configuredBaseUrl
      : fallbackBaseUrl).replace(/\/$/, '')
    const webhookUrl = `${supabaseUrl}/functions/v1/mp-webhook`
    const externalRef =
      `user_id=${user.id}|type=plan|plan=${encodeURIComponent(plan_nombre)}|creditos=${plan_creditos}|pago_id=${pago.id}`

    const mpPayload = {
      reason: `${plan_nombre} - Aura`,
      external_reference: externalRef,
      payer_email: payerEmail,
      back_url: `${appBaseUrl}/payment-result?status=success&pago_id=${pago.id}`,
      notification_url: webhookUrl,
      auto_recurring: {
        frequency: 1,
        frequency_type: 'months',
        transaction_amount: plan_precio,
        currency_id: 'ARS',
      },
      status: 'pending',
    }

    const mpRes = await fetch('https://api.mercadopago.com/preapproval', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${mpToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(mpPayload),
    })

    if (!mpRes.ok) {
      const errText = await mpRes.text()
      console.error('MP crear-checkout-plan error:', errText)
      await adminSupabase.from('pagos').delete().eq('id', pago.id)
      return json({ error: 'Error al crear suscripción en Mercado Pago: ' + errText }, 500)
    }

    const mpData = await mpRes.json()

    await adminSupabase
      .from('pagos')
      .update({
        mp_preapproval_id: String(mpData.id),
      })
      .eq('id', pago.id)

    return json({
      init_point: String(mpData.init_point ?? ''),
      preapproval_id: String(mpData.id ?? ''),
      pago_id: pago.id,
    })
  } catch (e) {
    console.error('crear-checkout-plan excepción:', e)
    return json({ error: 'Error interno del servidor' }, 500)
  }
})

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
