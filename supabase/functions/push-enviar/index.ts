// ============================================================================
// push-enviar — manda una notificación push (FCM v1) a los dispositivos de un
// usuario.
//
// La dispara el trigger `trg_notif_push_nueva` en `notificaciones_usuario`:
// TODO lo que genera campanita in-app se convierte en push, sin tocar ninguna
// de las funciones que notifican (promoción de lista de espera, aviso a
// profes, avisos del estudio...).
//
// Seguridad: verify_jwt=false + validación a mano del secreto compartido que
// manda el trigger en `x-push-secret`. Fail-CLOSED: sin secreto válido, 401.
//
// OJO: se usa FCM v1 (OAuth2 con service account). La API vieja de "server key"
// (fcm.googleapis.com/fcm/send) está DISCONTINUADA y devuelve 404.
// ============================================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const PUSH_SECRET = Deno.env.get('PUSH_TRIGGER_SECRET') ?? ''
const SA_B64 = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_B64') ?? ''

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })

// ── Firma del JWT para OAuth2 de Google ─────────────────────────────────────
function b64url(bytes: Uint8Array): string {
  let bin = ''
  for (const b of bytes) bin += String.fromCharCode(b)
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

function pemToPkcs8(pem: string): ArrayBuffer {
  const body = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '')
  const bin = atob(body)
  const buf = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i)
  return buf.buffer
}

interface ServiceAccount {
  client_email: string
  private_key: string
  project_id: string
}

let cachedToken: { value: string; exp: number } | null = null

async function getAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  // El token de Google dura 1h; se cachea por instancia para no re-firmar en
  // cada push (una promoción de lista de espera puede disparar varios).
  if (cachedToken && cachedToken.exp > now + 60) return cachedToken.value

  const enc = new TextEncoder()
  const header = b64url(enc.encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })))
  const claims = b64url(
    enc.encode(
      JSON.stringify({
        iss: sa.client_email,
        scope: 'https://www.googleapis.com/auth/firebase.messaging',
        aud: 'https://oauth2.googleapis.com/token',
        iat: now,
        exp: now + 3600,
      }),
    ),
  )
  const unsigned = `${header}.${claims}`

  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToPkcs8(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const sig = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    enc.encode(unsigned),
  )
  const jwt = `${unsigned}.${b64url(new Uint8Array(sig))}`

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  })
  const data = await res.json()
  if (!res.ok || !data.access_token) {
    throw new Error(`oauth_fallo: ${res.status} ${JSON.stringify(data)}`)
  }
  cachedToken = { value: data.access_token, exp: now + 3500 }
  return data.access_token
}

Deno.serve(async (req) => {
  // ── 1. Auth del trigger ───────────────────────────────────────────────────
  const secret = req.headers.get('x-push-secret') ?? ''
  if (!PUSH_SECRET || secret !== PUSH_SECRET) {
    return json({ error: 'No autorizado' }, 401)
  }

  if (!SA_B64) {
    return json({ error: 'FIREBASE_SERVICE_ACCOUNT_B64 no configurado' }, 500)
  }

  let sa: ServiceAccount
  try {
    sa = JSON.parse(atob(SA_B64))
  } catch (e) {
    return json({ error: 'service_account_invalido', detail: String(e) }, 500)
  }

  const body = await req.json().catch(() => ({}))
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)

  // ── 2. Qué mandar y a quién ───────────────────────────────────────────────
  let titulo = ''
  let mensaje = ''
  let tipo = ''
  let tokens: { token: string }[] = []

  if (body.test_token) {
    // Modo prueba: permite validar la autenticación contra FCM SIN un celular.
    // Con un token inventado, FCM debe responder NOT_FOUND/INVALID_ARGUMENT
    // (o sea: nos autenticó y solo rechazó el destinatario). Un 401 significa
    // que la credencial está mal.
    titulo = body.titulo ?? 'Prueba'
    mensaje = body.mensaje ?? 'Prueba de push'
    tipo = 'test'
    tokens = [{ token: String(body.test_token) }]
  } else {
    const { data: notif, error: notifErr } = await admin
      .from('notificaciones_usuario')
      .select('id, usuario_id, titulo, mensaje, tipo')
      .eq('id', body.notificacion_id)
      .maybeSingle()

    if (notifErr || !notif) {
      return json({ error: 'notificacion_no_encontrada' }, 404)
    }
    titulo = notif.titulo ?? 'Aura'
    mensaje = notif.mensaje ?? ''
    tipo = notif.tipo ?? ''

    const { data: disp } = await admin
      .from('dispositivos')
      .select('token')
      .eq('usuario_id', notif.usuario_id)
    tokens = disp ?? []
  }

  if (tokens.length === 0) {
    return json({ ok: true, enviados: 0, motivo: 'sin_dispositivos' })
  }

  // ── 3. Enviar ─────────────────────────────────────────────────────────────
  let accessToken: string
  try {
    accessToken = await getAccessToken(sa)
  } catch (e) {
    console.error('push-enviar: no se pudo autenticar contra Google:', String(e))
    return json({ error: 'oauth_fallo', detail: String(e) }, 500)
  }

  const url = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`
  const muertos: string[] = []
  const resultados: { token: string; status: number; error?: string }[] = []
  let enviados = 0

  for (const { token } of tokens) {
    const payload = {
      message: {
        token,
        notification: { title: titulo, body: mensaje },
        // `data` viaja para que el tap sepa a dónde ir.
        data: { tipo, titulo, mensaje },
        android: { priority: 'HIGH' },
        apns: {
          headers: { 'apns-priority': '10' },
          payload: { aps: { sound: 'default' } },
        },
      },
    }

    const res = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    })

    if (res.ok) {
      enviados++
      resultados.push({ token: token.slice(0, 12) + '…', status: res.status })
      continue
    }

    const err = await res.json().catch(() => ({}))
    const code = err?.error?.details?.[0]?.errorCode ?? err?.error?.status ?? ''
    resultados.push({
      token: token.slice(0, 12) + '…',
      status: res.status,
      error: code || JSON.stringify(err).slice(0, 200),
    })

    // Token muerto: el aparato desinstaló la app o el token rotó.
    // Si no se limpian, la tabla se llena de basura y cada push reintenta.
    if (code === 'UNREGISTERED' || code === 'INVALID_ARGUMENT' || res.status === 404) {
      muertos.push(token)
    }
  }

  if (muertos.length > 0 && !body.test_token) {
    await admin.from('dispositivos').delete().in('token', muertos)
  }

  return json({
    ok: true,
    enviados,
    fallidos: tokens.length - enviados,
    limpiados: body.test_token ? 0 : muertos.length,
    resultados,
  })
})
