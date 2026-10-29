// Manda eventos a la API de Conversiones de Meta (29/10/2026).
//
// Nadie espera a esta función: las de pago anotan el evento en
// meta_capi_eventos (con todo lo necesario en `payload`) y la llaman en
// segundo plano (ver _shared/meta_capi.ts). Si Meta no contesta, tarda o
// falta el token, el evento queda anotado y lo reintenta el cron
// `meta-capi-reintentos`, que llama acá con {"reintentar": true}.
//
// Dos formas de llamarla:
//   · Un evento (body = EventoMeta). Con la clave de servidor: cualquiera de
//     los tres. Con el token de una usuaria: sólo CompleteRegistration, y
//     sólo si la cuenta tiene menos de 7 días (lo pide la app web).
//   · {"reintentar": true}, sólo con la clave de servidor: manda lo pendiente.
//
// SECRETOS (nunca en el repo, que es público). Los busca primero en los
// secrets de las Edge Functions y, si no están, en el Vault de la base
// (get_meta_capi_config):
//   · META_PIXEL_ID           el píxel / conjunto de datos de Meta
//   · META_CAPI_ACCESS_TOKEN  el token de la API de Conversiones
//   · META_TEST_EVENT_CODE    OJO: mientras exista, TODO sale como evento de
//                             prueba. Borrarlo antes de salir a producción.
//
// No se manda nada de cuentas internas (cuentas_internas) ni de quien tenga
// usuarios.meta_tracking_opt_out = true: quedan como 'skipped'.

import { createClient } from 'npm:@supabase/supabase-js@2.57.4'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const DEFAULT_SOURCE_URL = 'https://somosaurapass.com/'
const ALLOWED_EVENTS = new Set(['CompleteRegistration', 'InitiateCheckout', 'Purchase'])

/// Tope para la respuesta de Meta.
const TOPE_META_MS = 10_000
/// Reintentos: cuántas veces como máximo, y sólo eventos de menos de 6 días
/// (Meta rechaza los de más de 7).
const MAX_INTENTOS = 5
const MAX_DIAS = 6
const LOTE_REINTENTO = 25

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)

type Config = { pixelId: string; token: string; testCode: string }
type Evento = Record<string, unknown>

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

async function sha256(value: string) {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(value.trim().toLowerCase()),
  )
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}

function firstIp(value: string | null) {
  return value?.split(',')[0]?.trim() || null
}

async function leerConfig(): Promise<Config> {
  let pixelId = Deno.env.get('META_PIXEL_ID')?.trim() || Deno.env.get('META_DATASET_ID')?.trim() || ''
  let token = Deno.env.get('META_CAPI_ACCESS_TOKEN')?.trim() || ''
  let testCode = Deno.env.get('META_TEST_EVENT_CODE')?.trim() || ''
  if (!token || !testCode) {
    const { data, error } = await admin.rpc('get_meta_capi_config')
    if (error) console.error('meta-capi-event: no se pudo leer el Vault:', error.message)
    token = token || String(data?.access_token ?? '').trim()
    testCode = testCode || String(data?.test_event_code ?? '').trim()
  }
  pixelId = pixelId.replace(/\D/g, '')
  return { pixelId, token, testCode }
}

async function marcar(eventId: string, cambios: Record<string, unknown>) {
  await admin
    .from('meta_capi_eventos')
    .update({ ...cambios, updated_at: new Date().toISOString() })
    .eq('event_id', eventId)
}

/// Manda UN evento ya anotado. Devuelve el estado final.
async function mandar(
  ev: Evento,
  config: Config,
  intentosPrevios: number,
  pedido?: Request,
): Promise<{ status: string; http?: number; detalle?: unknown }> {
  const eventId = String(ev.event_id)
  const eventName = String(ev.event_name)
  const userId = String(ev.user_id ?? '')
  const eventTime = Number(ev.event_time) || Math.floor(Date.now() / 1000)

  const { data: profile } = await admin
    .from('usuarios')
    .select('email, meta_tracking_opt_out')
    .eq('id', userId)
    .maybeSingle()
  const { data: authData } = await admin.auth.admin.getUserById(userId)
  const authUser = authData?.user
  const email = String(profile?.email ?? authUser?.email ?? '').trim().toLowerCase()
  const phone = String(authUser?.phone ?? '').replace(/\D/g, '')

  const { data: internal } = email
    ? await admin.from('cuentas_internas').select('email').eq('email', email).maybeSingle()
    : { data: null }
  if (profile?.meta_tracking_opt_out === true || internal) {
    await marcar(eventId, {
      status: 'skipped',
      last_error: profile?.meta_tracking_opt_out ? 'opt_out' : 'cuenta_interna',
    })
    return { status: 'skipped' }
  }

  // El clic de Meta de esta persona ANTERIOR al evento (el último).
  const { data: clic } = await admin
    .from('atribucion_meta')
    .select('fbc')
    .eq('usuario_id', userId)
    .lte('clic_at', new Date(eventTime * 1000).toISOString())
    .order('clic_at', { ascending: false })
    .limit(1)
    .maybeSingle()

  const userData: Record<string, unknown> = { external_id: [await sha256(userId)] }
  if (email) userData.em = [await sha256(email)]
  if (phone) userData.ph = [await sha256(phone)]
  if (clic?.fbc) userData.fbc = clic.fbc
  const clientIp = String(ev.client_ip ?? '') || (pedido ? firstIp(pedido.headers.get('x-forwarded-for')) : null)
  const clientUa = String(ev.client_user_agent ?? '') || (pedido ? pedido.headers.get('user-agent') : null)
  if (clientIp) userData.client_ip_address = clientIp
  if (clientUa) userData.client_user_agent = clientUa

  if (!userData.em && !userData.ph && !userData.fbc) {
    await marcar(eventId, { status: 'failed', last_error: 'Sin datos para que Meta reconozca a la persona' })
    return { status: 'failed' }
  }

  const customData: Record<string, unknown> = {}
  if (typeof ev.value === 'number') customData.value = ev.value
  if (ev.currency) customData.currency = String(ev.currency)
  if (ev.content_name) customData.content_name = String(ev.content_name)
  if (ev.content_type) customData.content_type = String(ev.content_type)

  const event: Record<string, unknown> = {
    event_name: eventName,
    event_time: eventTime,
    event_id: eventId,
    action_source: 'website',
    event_source_url: String(ev.event_source_url ?? DEFAULT_SOURCE_URL),
    user_data: userData,
  }
  if (Object.keys(customData).length) event.custom_data = customData

  // El token va en el CUERPO, no en la URL: las URLs suelen quedar en logs.
  const cuerpo: Record<string, unknown> = { data: [event], access_token: config.token }
  if (config.testCode) cuerpo.test_event_code = config.testCode

  await marcar(eventId, { status: 'pending', attempts: intentosPrevios + 1, last_error: null })

  let response: Response
  try {
    response = await fetch(`https://graph.facebook.com/${config.pixelId}/events`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(cuerpo),
      signal: AbortSignal.timeout(TOPE_META_MS),
    })
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e)
    await marcar(eventId, { status: 'failed', last_error: `Meta no contestó: ${msg}` })
    return { status: 'failed', detalle: msg }
  }
  const texto = await response.text()
  let metaResponse: unknown = texto
  try { metaResponse = JSON.parse(texto) } catch { /* queda el texto */ }

  if (!response.ok) {
    await marcar(eventId, {
      status: 'failed',
      meta_response: metaResponse,
      last_error: `Meta HTTP ${response.status}`,
    })
    return { status: 'failed', http: response.status, detalle: metaResponse }
  }
  await marcar(eventId, {
    status: 'delivered',
    meta_response: metaResponse,
    last_error: null,
    delivered_at: new Date().toISOString(),
  })
  return { status: 'delivered', detalle: metaResponse }
}

/// Manda lo que quedó pendiente o falló. Lo llama el cron.
async function reintentar(config: Config) {
  const desde = new Date(Date.now() - MAX_DIAS * 86_400_000).toISOString()
  const hace2min = new Date(Date.now() - 2 * 60_000).toISOString()
  const { data: filas, error } = await admin
    .from('meta_capi_eventos')
    .select('event_id, attempts, payload')
    .in('status', ['pending', 'failed'])
    .not('payload', 'is', null)
    .lt('attempts', MAX_INTENTOS)
    .gte('created_at', desde)
    .lt('updated_at', hace2min)
    .order('created_at', { ascending: true })
    .limit(LOTE_REINTENTO)
  if (error) return json({ error: error.message }, 500)
  const resultado: Record<string, number> = {}
  for (const f of filas ?? []) {
    try {
      const r = await mandar(f.payload as Evento, config, Number(f.attempts) || 0)
      resultado[r.status] = (resultado[r.status] ?? 0) + 1
    } catch (e) {
      console.error('meta-capi-event: reintento falló', f.event_id, e)
      resultado.error = (resultado.error ?? 0) + 1
    }
  }
  return json({ ok: true, revisados: filas?.length ?? 0, ...resultado })
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json({ error: 'Método no permitido' }, 405)

  let eventId = ''
  try {
    const bearer = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '').trim()
    if (!bearer) return json({ error: 'Sin autorización' }, 401)
    const serviceCall = bearer === SERVICE_ROLE_KEY

    const body = await req.json().catch(() => null) as Evento | null
    if (!body) return json({ error: 'JSON inválido' }, 400)

    const config = await leerConfig()
    // Sin píxel o sin token no se manda nada, pero lo anotado sigue pendiente
    // (sin gastar intentos): el cron lo manda cuando estén cargados.
    const faltaConfig = !config.pixelId
      ? 'META_PIXEL_ID no está configurado'
      : !config.token
      ? 'META_CAPI_ACCESS_TOKEN no está configurado'
      : null

    if (body.reintentar === true) {
      if (!serviceCall) return json({ error: 'No autorizado' }, 401)
      if (faltaConfig) return json({ error: faltaConfig }, 503)
      return await reintentar(config)
    }

    const eventName = String(body.event_name ?? '')
    if (!ALLOWED_EVENTS.has(eventName)) return json({ error: 'Evento no permitido' }, 400)

    let userId = serviceCall ? String(body.user_id ?? '') : ''
    let ev: Evento
    if (!serviceCall) {
      const userClient = createClient(SUPABASE_URL, ANON_KEY)
      const { data: { user }, error } = await userClient.auth.getUser(bearer)
      if (error || !user) return json({ error: 'Token de usuario inválido' }, 401)
      if (eventName !== 'CompleteRegistration') {
        return json({ error: 'Evento no permitido para cliente' }, 403)
      }
      userId = user.id
      // REGISTRO desde la app web (29/10/2026). La app lo pide en cada
      // entrada de una cuenta nueva; acá se decide si de verdad es un
      // registro: sólo cuentas de menos de 7 días (Meta rechaza eventos más
      // viejos). Una cuenta vieja que entra desde un anuncio NO es un registro.
      const altaMs = Date.parse(user.created_at ?? '')
      if (!Number.isFinite(altaMs) || Date.now() - altaMs > 7 * 86_400_000) {
        return json({ ok: true, status: 'ignored', motivo: 'la cuenta no es nueva' })
      }
      // Del cliente no se toma nada más que la página: un registro por
      // cuenta (mismo event_id siempre), a la hora real del alta, con la IP y
      // el navegador de este pedido (quedan anotados por si sale más tarde).
      const fuente = String(body.event_source_url ?? '')
      ev = {
        event_name: eventName,
        event_id: `registration:${userId}`,
        user_id: userId,
        event_time: Math.floor(altaMs / 1000),
        client_ip: firstIp(req.headers.get('x-forwarded-for')),
        client_user_agent: req.headers.get('user-agent'),
        event_source_url: fuente.startsWith('https://somosaurapass.com/') && fuente.length <= 300
          ? fuente
          : DEFAULT_SOURCE_URL,
      }
    } else {
      if (!userId) return json({ error: 'Falta user_id' }, 400)
      ev = {
        ...body,
        event_name: eventName,
        event_id: String(body.event_id ?? '').trim() || `${eventName.toLowerCase()}:${userId}`,
        user_id: userId,
        event_time: Number(body.event_time) || Math.floor(Date.now() / 1000),
      }
    }

    eventId = String(ev.event_id)
    if (eventId.length > 200) return json({ error: 'event_id demasiado largo' }, 400)

    // Anotarlo si quien llamó no lo hizo (no pisa uno ya anotado).
    await admin.from('meta_capi_eventos').upsert(
      {
        event_id: eventId,
        event_name: eventName,
        usuario_id: userId,
        pago_id: ev.pago_id || null,
        status: 'pending',
        payload: ev,
      },
      { onConflict: 'event_id', ignoreDuplicates: true },
    )
    const { data: fila } = await admin
      .from('meta_capi_eventos')
      .select('status, attempts, meta_response, payload')
      .eq('event_id', eventId)
      .maybeSingle()
    if (fila?.status === 'delivered' || fila?.status === 'skipped') {
      return json({ ok: true, duplicate: true, status: fila.status })
    }
    if (faltaConfig) return json({ error: faltaConfig, anotado: true }, 503)

    const r = await mandar((fila?.payload as Evento) ?? ev, config, Number(fila?.attempts) || 0, req)
    if (r.status === 'failed') return json({ error: 'Meta no recibió el evento', ...r }, 502)
    return json({ ok: true, event_id: eventId, ...r })
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    if (eventId) await marcar(eventId, { status: 'failed', last_error: message }).catch(() => {})
    console.error('meta-capi-event:', message)
    return json({ error: message }, 500)
  }
})
