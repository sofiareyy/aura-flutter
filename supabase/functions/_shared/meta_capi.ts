// Eventos para la API de Conversiones de Meta, SIN frenar a nadie (29/10/2026).
//
// La regla: un pago nunca espera a Meta. Antes crear-checkout-pack hacía
// `await fetch(meta-capi-event)` ANTES de devolver el link de pago: si Meta
// tardaba o no contestaba, el botón de pagar se quedaba girando.
//
// Ahora hay dos piezas:
//   · encolarEventoMeta: anota el evento en meta_capi_eventos con todo lo que
//     hace falta para mandarlo (payload). Es una escritura en NUESTRA base, no
//     una llamada a Meta.
//   · mandarEnSegundoPlano: le pide a meta-capi-event que lo mande, pero no lo
//     espera: el pedido corre con EdgeRuntime.waitUntil, después de que la
//     función ya respondió. Con tope de tiempo.
// Si el envío falla, o nunca llega a salir, el evento queda anotado y el cron
// `meta-capi-reintentos` lo vuelve a intentar (ver meta-capi-event).
//
// SÓLO COMPRAS WEB (decisión de Sofía, 29/10): quien llama decide con
// `esWeb()`. Las de la app del celular no se mandan.

// deno-lint-ignore no-explicit-any
type Admin = any

export type EventoMeta = {
  event_name: 'InitiateCheckout' | 'Purchase' | 'CompleteRegistration'
  event_id: string
  user_id: string
  pago_id?: string | null
  /// Segundos desde 1970. Se fija al anotarlo: un reintento manda la hora
  /// real del evento, no la del reintento.
  event_time: number
  value?: number
  currency?: string
  content_name?: string
  content_type?: string
  client_ip?: string | null
  client_user_agent?: string | null
  event_source_url?: string
}

/// ¿La compra se hizo desde la web? La app manda `platform: 'web' | 'mobile'`
/// desde abril de 2026. Cualquier otra cosa (o nada) cuenta como NO web.
export function esWeb(platform: unknown): boolean {
  return platform === 'web'
}

/// Tope para el pedido a meta-capi-event. Corre en segundo plano, así que no
/// demora a nadie; el tope es para no dejar un pedido colgado.
const TOPE_ENVIO_MS = 15_000

/// Anota el evento para mandarlo. Si ya estaba anotado (mismo event_id) no lo
/// pisa. Nunca lanza.
export async function encolarEventoMeta(admin: Admin, ev: EventoMeta): Promise<void> {
  try {
    const { error } = await admin.from('meta_capi_eventos').upsert(
      {
        event_id: ev.event_id,
        event_name: ev.event_name,
        usuario_id: ev.user_id,
        pago_id: ev.pago_id ?? null,
        status: 'pending',
        payload: ev,
      },
      { onConflict: 'event_id', ignoreDuplicates: true },
    )
    if (error) console.warn('meta: no se pudo anotar el evento', ev.event_id, error.message)
  } catch (e) {
    console.warn('meta: excepción anotando el evento', ev.event_id, e)
  }
}

/// Corre `tarea` después de responder, sin que la respuesta la espere.
/// EdgeRuntime.waitUntil es la forma de Supabase de mantener viva la función
/// hasta que termine; si no existe (local, tests), la promesa corre igual.
export function enSegundoPlano(tarea: Promise<unknown>): void {
  const p = tarea.catch((e) => console.warn('meta: tarea en segundo plano falló', e))
  try {
    // deno-lint-ignore no-explicit-any
    const rt = (globalThis as any).EdgeRuntime
    if (rt && typeof rt.waitUntil === 'function') rt.waitUntil(p)
  } catch (_) {
    // sin EdgeRuntime: la promesa ya está corriendo
  }
}

/// Le pide a meta-capi-event que mande el evento. Se usa SIEMPRE dentro de
/// `enSegundoPlano`: nadie lo espera.
export async function pedirEnvio(
  supabaseUrl: string,
  serviceKey: string,
  ev: EventoMeta,
): Promise<void> {
  const res = await fetch(`${supabaseUrl}/functions/v1/meta-capi-event`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${serviceKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(ev),
    signal: AbortSignal.timeout(TOPE_ENVIO_MS),
  })
  if (!res.ok) {
    // No es un error de la compra: el evento quedó anotado y lo reintenta el
    // cron. Por ejemplo, 503 mientras no esté cargado el token de Meta.
    console.warn(`meta: ${ev.event_name} ${ev.event_id} → ${res.status}`, await res.text())
  }
}

/// Primera IP del header x-forwarded-for.
export function ipDelPedido(req: Request): string | null {
  return req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || null
}
