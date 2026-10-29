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
    const {
      pack_nombre,
      creditos,
      amount,
      platform,
      gift_email,
      gift_mensaje,
      // El descuento que la app LE MOSTRÓ (versiones desde el 29/10/2026). No
      // decide nada: sólo sirve para avisar bien si dejó de aplicar.
      descuento_pct: descuentoMostrado,
    } = body ?? {}

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

    // 29/10/2026: descuento de primera compra. Lo decide SÓLO la base
    // (descuento_primera_compra), con el porcentaje de configuracion_global.
    // Las gift cards no llevan descuento.
    let descuentoPct = 0
    if (!isGift) {
      const { data: pct, error: pctErr } = await adminSupabase.rpc(
        'descuento_primera_compra',
        { p_user: user.id },
      )
      if (pctErr) {
        console.error('crear-checkout-pack: descuento_primera_compra falló:', pctErr.message)
        return json({ error: 'No se pudo preparar el pago. Probá de nuevo en un momento.' }, 500)
      }
      descuentoPct = typeof pct === 'number' && pct > 0 && pct < 100 ? pct : 0
    }
    const precioLista = Math.round(packConfig.amount)
    const montoFinal = descuentoPct > 0
      ? precioConDescuento(precioLista, descuentoPct)
      : precioLista

    // La app mostró un descuento que ya no le corresponde (por ejemplo, otra
    // compra se aprobó mientras tanto). Se avisa en vez de cobrarle otro monto.
    if (
      descuentoPct === 0 &&
      typeof descuentoMostrado === 'number' &&
      descuentoMostrado > 0
    ) {
      return json(
        {
          error:
            'El descuento de primera compra ya no aplica a tu cuenta. ' +
            'Volvé a los packs para ver el precio.',
          codigo: 'descuento_no_disponible',
        },
        409,
      )
    }

    // El `amount` del cliente no fija el precio, pero sirve para detectar que
    // la app está desactualizada: si muestra un precio y la tabla tiene otro,
    // se le cobraría algo distinto de lo que vio. Mejor frenar y pedirle que
    // actualice que cobrarle de más en silencio.
    // Con descuento se acepta también el precio de lista: es una app anterior
    // al descuento que no sabe mostrarlo. Se le cobra MENOS de lo que vio, y
    // Mercado Pago le muestra el monto real antes de pagar.
    const montoCliente = Math.round(amount)
    const montoAceptado = montoCliente === montoFinal ||
      (descuentoPct > 0 && montoCliente === precioLista)
    if (!montoAceptado) {
      console.warn(
        `crear-checkout-pack: precio desactualizado en el cliente. ` +
          `pack=${packConfig.nombre} cliente=${amount} tabla=${packConfig.amount} ` +
        `descuento=${descuentoPct}`,
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

    const mpToken = Deno.env.get('MP_PACKS_ACCESS_TOKEN')!

    // Un solo checkout con descuento pagable a la vez: si abrió otro antes y
    // no lo pagó, ese link se vence ahora. Así no se puede pagar dos veces con
    // descuento abriendo dos pestañas.
    if (descuentoPct > 0) {
      await vencerCheckoutsConDescuento(adminSupabase, user.id, mpToken)
    }

    const { data: pago, error: pagoErr } = await adminSupabase
      .from('pagos')
      .insert({
        user_id: user.id,
        type: isGift ? 'gift' : 'pack',
        status: 'pending',
        amount: montoFinal,
        precio_lista: precioLista,
        descuento_pct: descuentoPct,
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
            : descuentoPct > 0
            ? `${packConfig.nombre} - ${packConfig.creditos} créditos Aura (${descuentoPct}% off primera compra)`
            : `${packConfig.nombre} - ${packConfig.creditos} créditos Aura`,
          description: isGift
            ? `Gift card de créditos Aura para regalar`
            : `Pack de créditos Aura - ${packConfig.nombre}`,
          category_id: 'services',
          quantity: 1,
          unit_price: montoFinal,
          currency_id: 'ARS',
        },
      ],
      // Con descuento: el link vence a los 30 minutos y no se puede pagar en
      // efectivo (Rapipago / Pago Fácil). Esos pagos quedan "pendientes" días
      // y abrirían la puerta a usar el descuento dos veces.
      ...(descuentoPct > 0 && {
        expires: true,
        expiration_date_from: fechaMp(new Date()),
        expiration_date_to: fechaMp(new Date(Date.now() + VENCE_CHECKOUT_DESCUENTO_MS)),
        payment_methods: {
          excluded_payment_types: [{ id: 'ticket' }, { id: 'atm' }],
        },
      }),
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

    const metaClientIp = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ?? null
    const metaClientUserAgent = req.headers.get('user-agent')
    await adminSupabase
      .from('pagos')
      .update({
        meta_client_ip: metaClientIp,
        meta_client_user_agent: metaClientUserAgent,
      })
      .eq('id', pago.id)

    try {
      const metaRes = await fetch(`${supabaseUrl}/functions/v1/meta-capi-event`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          event_name: 'InitiateCheckout',
          event_id: `checkout:${pago.id}`,
          user_id: user.id,
          pago_id: pago.id,
          value: montoFinal,
          currency: 'ARS',
          content_name: packConfig.nombre,
          content_type: 'product',
          client_ip: metaClientIp,
          client_user_agent: metaClientUserAgent,
          event_source_url: 'https://somosaurapass.com/#/landing',
        }),
      })
      if (!metaRes.ok) {
        console.warn('crear-checkout-pack: Meta InitiateCheckout no enviado:', await metaRes.text())
      }
    } catch (metaError) {
      console.warn('crear-checkout-pack: error enviando Meta InitiateCheckout:', metaError)
    }

    return json({
      init_point: String(mpData.init_point ?? mpData.sandbox_init_point ?? ''),
      sandbox_init_point: String(mpData.sandbox_init_point ?? ''),
      preference_id: String(mpData.id),
      pago_id: pago.id,
      amount: montoFinal,
      descuento_pct: descuentoPct,
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

/// Cuánto dura el link de pago con descuento.
const VENCE_CHECKOUT_DESCUENTO_MS = 30 * 60 * 1000

/// Precio con descuento, redondeado al peso. La app usa la MISMA cuenta
/// (pricing_service.dart, precioConDescuento): si cambiás una, cambiá la otra.
function precioConDescuento(precio: number, pct: number): number {
  return Math.floor((precio * (100 - pct) + 50) / 100)
}

/// Fecha en el formato que pide Mercado Pago, en hora argentina
/// (2026-10-29T10:00:00.000-03:00). Argentina no tiene horario de verano.
function fechaMp(d: Date): string {
  const art = new Date(d.getTime() - 3 * 60 * 60 * 1000)
  return art.toISOString().replace('Z', '-03:00')
}

/// Vence en Mercado Pago los checkouts con descuento que la persona abrió y
/// no pagó. Si falla, sigue: cada link vence solo a los 30 minutos igual.
async function vencerCheckoutsConDescuento(
  // deno-lint-ignore no-explicit-any
  adminSupabase: any,
  userId: string,
  mpToken: string,
): Promise<void> {
  try {
    const { data: abiertos } = await adminSupabase
      .from('pagos')
      .select('id, mp_preference_id')
      .eq('user_id', userId)
      .eq('type', 'pack')
      .eq('status', 'pending')
      .gt('descuento_pct', 0)
      .is('mp_payment_id', null)
      .not('mp_preference_id', 'is', null)
    for (const p of abiertos ?? []) {
      const res = await fetch(
        `https://api.mercadopago.com/checkout/preferences/${p.mp_preference_id}`,
        {
          method: 'PUT',
          headers: {
            Authorization: `Bearer ${mpToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ expires: true, expiration_date_to: fechaMp(new Date()) }),
        },
      )
      if (!res.ok) {
        console.warn(
          `crear-checkout-pack: no se pudo vencer la preferencia ${p.mp_preference_id}: ` +
            (await res.text()),
        )
      }
    }
  } catch (e) {
    console.warn('crear-checkout-pack: vencerCheckoutsConDescuento falló:', e)
  }
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
