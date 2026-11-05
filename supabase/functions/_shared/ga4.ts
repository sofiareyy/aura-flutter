// Google Analytics 4 desde el servidor: el paso 8 del embudo, "Compró" (5/11/2026).
//
// La compra la confirma Mercado Pago al servidor (mp-webhook), sin navegador:
// mucha gente no vuelve a la página después de pagar. Para que GA4 la una a la
// visita que vino del anuncio, el checkout guarda en el pago el identificador
// de GA de ese navegador (client_id), la visita (session_id) y la campaña
// (utm_*, fbclid). Acá se lee eso y se manda por el Measurement Protocol.
//
// Reglas:
// - Sólo compras web con client_id (la app no tiene GA).
// - Nunca cuentas internas o de prueba (cuentas_internas).
// - Una vez por pago: `pagos.ga_compra_at` se marca ANTES de mandar.
// - Sin mail, nombre ni teléfono: el usuario va como su id interno.
// - Nunca lanza y corre en segundo plano: la acreditación no espera a Google.
// - Sin el secret GA_API_SECRET no hace nada (lo crea Sofía en GA4).

export const GA_MEASUREMENT_ID = 'G-CLBKV39C1M'
const CAMPOS_ATRIB = ['utm_source', 'utm_medium', 'utm_campaign', 'utm_content', 'fbclid']
const TOPE_MS = 10_000

export type DatosGa = {
  ga_client_id: string | null
  ga_session_id: string | null
  atribucion: Record<string, string> | null
}

/** Lo que manda la app en `body.ga`, limpio. Fuera de la web, nada. */
export function datosGaDelPedido(ga: unknown, esWeb: boolean): DatosGa {
  const vacio = { ga_client_id: null, ga_session_id: null, atribucion: null }
  if (!esWeb || !ga || typeof ga !== 'object') return vacio
  const g = ga as Record<string, unknown>
  const clientId = typeof g.client_id === 'string' && /^\d{1,20}\.\d{1,20}$/.test(g.client_id) ? g.client_id : null
  const sessionId = typeof g.session_id === 'string' && /^\d{1,20}$/.test(g.session_id) ? g.session_id : null
  let atribucion: Record<string, string> | null = null
  if (g.atribucion && typeof g.atribucion === 'object') {
    const a = g.atribucion as Record<string, unknown>
    for (const k of CAMPOS_ATRIB) {
      const v = a[k]
      if (typeof v === 'string' && v.trim()) {
        atribucion = atribucion ?? {}
        atribucion[k] = v.trim().slice(0, 100)
      }
    }
  }
  return { ga_client_id: clientId, ga_session_id: sessionId, atribucion }
}

/** El cuerpo del pedido a GA4. Separado para poder probarlo. */
export function armarCompraGa(input: {
  clientId: string
  sessionId: string | null
  userId: string
  transactionId: string
  value: number
  itemName: string
  itemCategory: string
  atribucion: Record<string, string> | null
}) {
  const params: Record<string, unknown> = {
    transaction_id: input.transactionId,
    value: input.value,
    currency: 'ARS',
    items: [{ item_name: input.itemName, item_category: input.itemCategory, price: input.value, quantity: 1 }],
    engagement_time_msec: 1,
  }
  if (input.sessionId) params.session_id = input.sessionId
  for (const [k, v] of Object.entries(input.atribucion ?? {})) {
    if (CAMPOS_ATRIB.includes(k)) params[k] = v
  }
  return {
    client_id: input.clientId,
    user_id: input.userId,
    events: [{ name: 'purchase', params }],
  }
}

// deno-lint-ignore no-explicit-any
type Admin = any

/** "Compró" a GA4 para el pago `pagoIdCheckout` (la fila que armó el checkout). */
export async function mandarCompraGa(admin: Admin, input: {
  pagoIdCheckout: string
  userId: string
  value: number
  itemName: string
  itemCategory: 'pack' | 'regalo' | 'plan'
}): Promise<void> {
  try {
    const secret = Deno.env.get('GA_API_SECRET') ?? ''
    if (!secret || !input.pagoIdCheckout) return

    const { data: p } = await admin.from('pagos')
      .select('id, user_id, plataforma, ga_client_id, ga_session_id, atribucion, ga_compra_at')
      .eq('id', input.pagoIdCheckout).maybeSingle()
    if (!p || p.user_id !== input.userId || p.plataforma !== 'web' || !p.ga_client_id || p.ga_compra_at) return

    const { data: u } = await admin.auth.admin.getUserById(input.userId)
    const email = String(u?.user?.email ?? '').trim().toLowerCase()
    if (email) {
      const { data: interna } = await admin.from('cuentas_internas').select('email').eq('email', email).maybeSingle()
      if (interna) return
    }

    // Una sola vez por pago, aunque Mercado Pago avise dos veces.
    const { data: tomada } = await admin.from('pagos')
      .update({ ga_compra_at: new Date().toISOString() })
      .eq('id', p.id).is('ga_compra_at', null).select('id')
    if (!tomada || tomada.length === 0) return

    const cuerpo = armarCompraGa({
      clientId: p.ga_client_id,
      sessionId: p.ga_session_id,
      userId: input.userId,
      transactionId: String(p.id),
      value: input.value,
      itemName: input.itemName,
      itemCategory: input.itemCategory,
      atribucion: p.atribucion,
    })
    const ctrl = new AbortController()
    const t = setTimeout(() => ctrl.abort(), TOPE_MS)
    const res = await fetch(
      `https://www.google-analytics.com/mp/collect?measurement_id=${GA_MEASUREMENT_ID}&api_secret=${encodeURIComponent(secret)}`,
      { method: 'POST', body: JSON.stringify(cuerpo), signal: ctrl.signal },
    ).finally(() => clearTimeout(t))
    if (!res.ok) {
      console.warn(`ga4: purchase ${p.id} → ${res.status}`)
      // Se libera para que un reaviso de Mercado Pago lo reintente.
      await admin.from('pagos').update({ ga_compra_at: null }).eq('id', p.id)
    }
  } catch (e) {
    console.warn('ga4: no se pudo mandar la compra', e)
  }
}
