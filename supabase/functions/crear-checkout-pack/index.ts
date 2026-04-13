// Crea una preferencia de pago único en Mercado Pago y registra el pago pendiente en la DB.
// Llamada desde Flutter con el JWT del usuario autenticado.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const jwt = req.headers.get('x-aura-auth')?.trim() ?? ''
    if (!jwt) {
      return json({ error: 'Sin autorización' }, 401)
    }

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
    const { pack_nombre, creditos, amount, vigencia_dias } = body ?? {}

    if (!pack_nombre || typeof creditos !== 'number' || typeof amount !== 'number') {
      return json({ error: 'Faltan campos: pack_nombre, creditos, amount' }, 400)
    }
    const packConfig = await resolvePackConfig(adminSupabase, pack_nombre, creditos, amount, vigencia_dias)
    const payerEmail = user.email ?? ''
    if (!payerEmail) {
      return json({ error: 'No encontramos un email válido para el pago.' }, 400)
    }

    const { data: pago, error: pagoErr } = await adminSupabase
      .from('pagos')
      .insert({
        user_id: user.id,
        type: 'pack',
        status: 'pending',
        amount: Math.round(packConfig.amount),
        creditos: packConfig.creditos,
        pack_nombre: packConfig.nombre,
      })
      .select('id')
      .single()

    if (pagoErr || !pago?.id) {
      console.error('Error insertando pago pack antes de checkout:', pagoErr?.message)
      return json({ error: 'No se pudo preparar el pago.' }, 500)
    }

    const mpToken = Deno.env.get('MP_PACKS_ACCESS_TOKEN') ?? Deno.env.get('MP_ACCESS_TOKEN')!
    const configuredBaseUrl = Deno.env.get('APP_BASE_URL')?.trim() ?? ''
    const requestOrigin = req.headers.get('origin')?.trim() ?? ''
    const requestReferer = req.headers.get('referer')?.trim() ?? ''
    const refererOrigin = requestReferer ? new URL(requestReferer).origin : ''
    const fallbackBaseUrl = requestOrigin || refererOrigin || 'http://localhost:3000'
    const appBaseUrl = ((configuredBaseUrl && !configuredBaseUrl.includes('example.com')) ? configuredBaseUrl : fallbackBaseUrl).replace(/\/$/, '')
    const webhookUrl = `${supabaseUrl}/functions/v1/mp-webhook`
    const externalRef = `user_id=${user.id}|type=pack|pack=${encodeURIComponent(packConfig.nombre)}|creditos=${packConfig.creditos}|vigencia=${packConfig.vigenciaDias}|pago_id=${pago.id}`
    const backUrls = {
      success: `${appBaseUrl}/payment-result?status=success&pago_id=${pago.id}`,
      failure: `${appBaseUrl}/payment-result?status=failure&pago_id=${pago.id}`,
      pending: `${appBaseUrl}/payment-result?status=pending&pago_id=${pago.id}`,
    }

    const mpPayload = {
      items: [
        {
          id: `pack_${packConfig.nombre.toLowerCase().replace(/\s+/g, '_')}`,
          title: `${packConfig.nombre} - ${packConfig.creditos} créditos Aura`,
          quantity: 1,
          unit_price: Math.round(packConfig.amount),
          currency_id: 'ARS',
        },
      ],
      payer: { email: payerEmail },
      notification_url: webhookUrl,
      back_urls: backUrls,
      auto_return: 'approved',
      external_reference: externalRef,
    }

    const mpRes = await fetch('https://api.mercadopago.com/checkout/preferences', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${mpToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(mpPayload),
    })

    if (!mpRes.ok) {
      const errText = await mpRes.text()
      console.error('MP crear-checkout-pack error:', errText)
      await adminSupabase.from('pagos').delete().eq('id', pago.id)
      return json({ error: 'Error al crear checkout en Mercado Pago: ' + errText }, 500)
    }

    const mpData = await mpRes.json()

    const { error: updatePagoErr } = await adminSupabase
      .from('pagos')
      .update({
        mp_preference_id: String(mpData.id),
      })
      .eq('id', pago.id)

    if (updatePagoErr) {
      console.error('Error actualizando pago pack:', updatePagoErr.message)
    }

    return json({
      init_point: String(mpData.init_point ?? mpData.sandbox_init_point ?? ''),
      sandbox_init_point: String(mpData.sandbox_init_point ?? ''),
      preference_id: String(mpData.id),
      pago_id: pago.id,
    })
  } catch (e) {
    console.error('crear-checkout-pack excepción:', e)
    return json({ error: 'Error interno del servidor' }, 500)
  }
})

// Lee el pack desde pricing_credit_packs en Supabase.
// Si no lo encuentra, usa los valores del body como fallback.
async function resolvePackConfig(
  // deno-lint-ignore no-explicit-any
  adminSupabase: any,
  packNombre: string,
  creditos: number,
  amount: number,
  vigenciaDias?: number,
) {
  try {
    const { data } = await adminSupabase
      .from('pricing_credit_packs')
      .select('nombre, creditos, precio, vencimiento_dias')
      .eq('activo', true)
      .or(`nombre.ilike.${packNombre.trim()},creditos.eq.${creditos}`)
      .maybeSingle()

    if (data) {
      return {
        nombre: data.nombre as string,
        creditos: data.creditos as number,
        amount: data.precio as number,
        vigenciaDias: (data.vencimiento_dias as number) ?? 90,
      }
    }
  } catch (e) {
    console.warn('resolvePackConfig: error leyendo pricing_credit_packs, usando fallback:', e)
  }

  // Fallback: valores enviados desde Flutter
  return {
    nombre: packNombre,
    creditos,
    amount,
    vigenciaDias: typeof vigenciaDias === 'number' && vigenciaDias > 0 ? vigenciaDias : 90,
  }
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
