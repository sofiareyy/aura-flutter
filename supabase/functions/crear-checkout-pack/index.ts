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
    // `vigencia_dias` ya no se lee del body: el vencimiento lo decide
    // pricing_credit_packs.vencimiento_dias.
    const { pack_nombre, creditos, amount, platform, gift_email, gift_mensaje } = body ?? {}

    if (!pack_nombre || typeof creditos !== 'number' || typeof amount !== 'number') {
      return json({ error: 'Faltan campos: pack_nombre, creditos, amount' }, 400)
    }

    // Gift card: mismo flujo que un pack, pero con destinatario. El pago lo hace
    // el comprador; al aprobarse, en vez de acreditarle créditos, se crea el
    // regalo y se mailea al destinatario.
    const giftEmail = typeof gift_email === 'string' ? gift_email.trim().toLowerCase() : ''
    const isGift = giftEmail.length > 0
    if (isGift && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(giftEmail)) {
      return json({ error: 'Email de destinatario inválido' }, 400)
    }
    const giftMensaje = typeof gift_mensaje === 'string' ? gift_mensaje.trim() : ''
    // El precio SIEMPRE sale de pricing_credit_packs. Si el pack no está en
    // la tabla, se rechaza en vez de confiar en el `amount` del cliente.
    const packConfig = await resolvePackConfig(adminSupabase, pack_nombre, creditos)
    if (!packConfig) {
      return json(
        { error: 'Ese pack ya no está disponible. Actualizá la app y probá de nuevo.' },
        409,
      )
    }

    // El `amount` del cliente no fija el precio, pero sirve para detectar que
    // la app está desactualizada: si muestra un precio y la tabla tiene otro,
    // se le cobraría algo distinto de lo que vio. Mejor frenar y pedirle que
    // actualice que cobrarle de más en silencio.
    if (Math.round(amount) !== Math.round(packConfig.amount)) {
      console.warn(
        `crear-checkout-pack: precio desactualizado en el cliente. ` +
          `pack=${packConfig.nombre} cliente=${amount} tabla=${packConfig.amount}`,
      )
      return json(
        {
          error: 'Los precios cambiaron. Actualizá la app para ver los valores nuevos.',
          codigo: 'precio_desactualizado',
        },
        409,
      )
    }
    const payerEmail = user.email ?? ''
    if (!payerEmail) {
      return json({ error: 'No encontramos un email válido para el pago.' }, 400)
    }

    // Obtener nombre del usuario para mejorar tasa de aprobación en MP
    const { data: usuarioRow } = await adminSupabase
      .from('usuarios')
      .select('nombre')
      .eq('id', user.id)
      .maybeSingle()
    const nombreCompleto = (usuarioRow?.nombre as string | null)?.trim() ?? ''
    const [firstName, ...restParts] = nombreCompleto.split(' ')
    const payerFirstName = firstName ?? ''
    const payerLastName = restParts.join(' ')

    const { data: pago, error: pagoErr } = await adminSupabase
      .from('pagos')
      .insert({
        user_id: user.id,
        type: isGift ? 'gift' : 'pack',
        status: 'pending',
        amount: Math.round(packConfig.amount),
        creditos: packConfig.creditos,
        pack_nombre: packConfig.nombre,
        gift_email: isGift ? giftEmail : null,
        gift_mensaje: isGift && giftMensaje ? giftMensaje : null,
      })
      .select('id')
      .single()

    if (pagoErr || !pago?.id) {
      console.error('Error insertando pago pack antes de checkout:', pagoErr?.message)
      return json({ error: 'No se pudo preparar el pago.' }, 500)
    }

    const mpToken = Deno.env.get('MP_PACKS_ACCESS_TOKEN')!
    const configuredBaseUrl = Deno.env.get('APP_BASE_URL')?.trim() ?? ''
    const requestOrigin = req.headers.get('origin')?.trim() ?? ''
    const requestReferer = req.headers.get('referer')?.trim() ?? ''
    const refererOrigin = requestReferer ? new URL(requestReferer).origin : ''
    const fallbackBaseUrl = requestOrigin || refererOrigin || 'http://localhost:3000'
    const appBaseUrl = ((configuredBaseUrl && !configuredBaseUrl.includes('example.com')) ? configuredBaseUrl : fallbackBaseUrl).replace(/\/$/, '')
    const webhookUrl = `${supabaseUrl}/functions/v1/mp-webhook`
    const externalRef = `user_id=${user.id}|type=${isGift ? 'gift' : 'pack'}|pack=${encodeURIComponent(packConfig.nombre)}|creditos=${packConfig.creditos}|vigencia=${packConfig.vigenciaDias}|pago_id=${pago.id}`
    const isMobile = platform === 'mobile'
    const backUrlBase = isMobile ? 'aura://payment-result' : `${appBaseUrl}/payment-result`
    const backUrls = {
      success: `${backUrlBase}?status=success&pago_id=${pago.id}`,
      failure: `${backUrlBase}?status=failure&pago_id=${pago.id}`,
      pending: `${backUrlBase}?status=pending&pago_id=${pago.id}`,
    }

    const mpPayload = {
      items: [
        {
          id: `${isGift ? 'gift' : 'pack'}_${packConfig.nombre.toLowerCase().replace(/\s+/g, '_')}`,
          title: isGift
            ? `Gift card Aura - ${packConfig.creditos} créditos`
            : `${packConfig.nombre} - ${packConfig.creditos} créditos Aura`,
          description: isGift
            ? `Gift card de créditos Aura para regalar`
            : `Pack de créditos Aura - ${packConfig.nombre}`,
          category_id: 'services',
          quantity: 1,
          unit_price: Math.round(packConfig.amount),
          currency_id: 'ARS',
        },
      ],
      payer: {
        email: payerEmail,
        ...(payerFirstName && { first_name: payerFirstName }),
        ...(payerLastName && { last_name: payerLastName }),
      },
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
/// Busca el pack en `pricing_credit_packs`. Devuelve null si no existe o si
/// falla la lectura.
///
/// El precio del body se ignora por completo. Antes, si no encontraba el
/// pack, cobraba el `amount` que mandaba el cliente: cualquiera podía comprar
/// 200 créditos por $1 armando el request a mano, y una app vieja con precios
/// desactualizados cobraba el precio viejo sin que se notara.
///
/// Las gift cards pasan por acá también, pero siempre con uno de los 4 packs
/// canónicos, así que no las afecta.
async function resolvePackConfig(
  // deno-lint-ignore no-explicit-any
  adminSupabase: any,
  packNombre: string,
  creditos: number,
): Promise<
  { nombre: string; creditos: number; amount: number; vigenciaDias: number } | null
> {
  const nombre = (packNombre ?? '').trim()
  const cols = 'nombre, creditos, precio, vencimiento_dias'
  try {
    // Por nombre exacto primero. El match por créditos va como respaldo en
    // una consulta aparte: con `.or()` podían matchear dos filas y
    // maybeSingle() devolvía null, cayendo al fallback inseguro.
    const { data: porNombre } = await adminSupabase
      .from('pricing_credit_packs')
      .select(cols)
      .eq('activo', true)
      .ilike('nombre', nombre)
      .maybeSingle()

    const data = porNombre ?? (
      await adminSupabase
        .from('pricing_credit_packs')
        .select(cols)
        .eq('activo', true)
        .eq('creditos', creditos)
        .maybeSingle()
    ).data

    if (data) {
      const dias = data.vencimiento_dias as number | null
      return {
        nombre: data.nombre as string,
        creditos: data.creditos as number,
        amount: data.precio as number,
        vigenciaDias: dias != null && dias > 0 ? dias : 60,
      }
    }
  } catch (e) {
    console.error('resolvePackConfig: error leyendo pricing_credit_packs:', e)
  }

  return null
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
