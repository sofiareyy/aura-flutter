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
    const { plan_nombre, plan_creditos, plan_precio, platform } = body ?? {}

    if (!plan_nombre || typeof plan_creditos !== 'number' || typeof plan_precio !== 'number') {
      return json({ error: 'Faltan campos: plan_nombre, plan_creditos, plan_precio' }, 400)
    }

    const payerEmail = user.email ?? ''
    if (!payerEmail) {
      return json({ error: 'No encontramos un email válido para la suscripción.' }, 400)
    }

    // El precio SIEMPRE sale de pricing_planes. Si el plan no está en la
    // tabla, se rechaza: antes se caía a los valores del body, así que
    // cualquiera podía suscribirse al precio que quisiera mandando
    // plan_precio, y una app vieja con un plan renombrado cobraba el precio
    // viejo sin que nadie lo notara.
    const planConfig = await resolvePlanConfig(adminSupabase, plan_nombre, plan_creditos)
    if (!planConfig) {
      return json(
        { error: 'Ese plan ya no está disponible. Actualizá la app y probá de nuevo.' },
        409,
      )
    }

    // Igual que en los packs: si la app muestra un precio distinto al de la
    // tabla, está desactualizada. Se frena antes de armar la suscripción, para
    // no dejarle un débito mensual por un monto que nunca vio.
    if (Math.round(plan_precio) !== Math.round(planConfig.precio)) {
      console.warn(
        `crear-checkout-plan: precio desactualizado en el cliente. ` +
          `plan=${planConfig.nombre} cliente=${plan_precio} tabla=${planConfig.precio}`,
      )
      return json(
        {
          error: 'Los precios cambiaron. Actualizá la app para ver los valores nuevos.',
          codigo: 'precio_desactualizado',
        },
        409,
      )
    }

    const { data: pago, error: pagoErr } = await adminSupabase
      .from('pagos')
      .insert({
        user_id: user.id,
        type: 'plan',
        status: 'pending',
        amount: Math.round(planConfig.precio),
        creditos: planConfig.creditos,
        plan_nombre: planConfig.nombre,
      })
      .select('id')
      .single()

    if (pagoErr || !pago?.id) {
      console.error('Error insertando pago plan:', pagoErr?.message)
      return json({ error: 'No se pudo preparar la suscripción.' }, 500)
    }

    const mpToken =
      Deno.env.get('MP_SUBSCRIPTIONS_ACCESS_TOKEN') ??
      Deno.env.get('MP_SUSCRIPCIONES_ACCESS_TOKEN')!

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
      `user_id=${user.id}|type=plan|plan=${encodeURIComponent(planConfig.nombre)}|creditos=${planConfig.creditos}|pago_id=${pago.id}`

    const isMobile = platform === 'mobile'
    const backUrlBase = isMobile ? 'aura://payment-result' : `${appBaseUrl}/payment-result`

    const mpPayload = {
      reason: `${planConfig.nombre} - ${planConfig.creditos} créditos Aura/mes`,
      external_reference: externalRef,
      payer_email: payerEmail,
      back_url: `${backUrlBase}?status=success&pago_id=${pago.id}`,
      notification_url: webhookUrl,
      auto_recurring: {
        frequency: 1,
        frequency_type: 'months',
        transaction_amount: Math.round(planConfig.precio),
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
      .update({ mp_preapproval_id: String(mpData.id) })
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

/// Busca el plan en `pricing_planes`. Devuelve null si no existe o si falla
/// la lectura: sin plan confirmado no se crea ninguna suscripción.
///
/// El precio del body se ignora por completo — solo se usa para comparar y
/// dejar registro si difiere.
async function resolvePlanConfig(
  // deno-lint-ignore no-explicit-any
  adminSupabase: any,
  planNombre: string,
  creditos: number,
): Promise<{ nombre: string; creditos: number; precio: number } | null> {
  const nombre = (planNombre ?? '').trim()
  try {
    // Primero por nombre exacto. El match por créditos queda como respaldo
    // aparte: con `.or()` en una sola consulta, dos planes podían matchear y
    // maybeSingle() devolvía null (o el equivocado).
    const { data: porNombre } = await adminSupabase
      .from('pricing_planes')
      .select('nombre, creditos, precio')
      .eq('activo', true)
      .ilike('nombre', nombre)
      .maybeSingle()

    const data = porNombre ?? (
      await adminSupabase
        .from('pricing_planes')
        .select('nombre, creditos, precio')
        .eq('activo', true)
        .eq('creditos', creditos)
        .maybeSingle()
    ).data

    if (data) {
      return {
        nombre: data.nombre as string,
        creditos: data.creditos as number,
        precio: data.precio as number,
      }
    }
  } catch (e) {
    console.error('resolvePlanConfig: error leyendo pricing_planes:', e)
  }

  return null
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
