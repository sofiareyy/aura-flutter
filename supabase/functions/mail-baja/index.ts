// mail-baja — registra que alguien no quiere recibir más mails de Aura que no
// sean avisos de reservas o pagos (regalos, invitaciones, bienvenida).
//
// La llaman dos lados, los dos sin login:
// 1. La página somosaurapass.com/baja.html (link al pie de cada mail), con un
//    POST JSON {u, t, accion}. accion = 'baja' (default) o 'alta' (el botón
//    "fue sin querer" de esa misma página).
// 2. El botón "Anular suscripción" de Gmail, que hace un POST a la URL del
//    encabezado List-Unsubscribe con `List-Unsubscribe=One-Click` (RFC 8058).
//    En ese caso u y t vienen en la URL.
//
// Seguridad: verify_jwt = false (es pública a propósito); lo que autoriza es
// la firma `t`, un HMAC del id con MAIL_BAJA_SECRET. Sin firma válida, 403.
// Un GET no hace nada: los antivirus de algunos correos "abren" los links para
// revisarlos y no queremos bajas que nadie pidió.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { firmaValida } from '../_shared/baja.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const SECRETO = Deno.env.get('MAIL_BAJA_SECRET') ?? ''

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: 'Usá POST' }, 405)
  if (!SECRETO) return json({ error: 'MAIL_BAJA_SECRET no configurado' }, 500)

  try {
    const url = new URL(req.url)
    let u = url.searchParams.get('u') ?? ''
    let t = url.searchParams.get('t') ?? ''
    let accion = 'baja'
    let origen: 'link' | 'gmail' = 'gmail'

    const tipo = req.headers.get('content-type') ?? ''
    if (tipo.includes('application/json')) {
      const body = await req.json().catch(() => ({}))
      u = String(body?.u ?? u)
      t = String(body?.t ?? t)
      accion = body?.accion === 'alta' ? 'alta' : 'baja'
      origen = 'link'
    } else {
      // One-Click de Gmail: el cuerpo es "List-Unsubscribe=One-Click".
      await req.text().catch(() => '')
    }

    u = u.trim().toLowerCase()
    if (!UUID.test(u) || !(await firmaValida(u, t.trim(), SECRETO))) {
      return json({ error: 'Link inválido' }, 403)
    }

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)
    const email = await emailDe(admin, u)
    if (!email) return json({ error: 'No encontramos esa cuenta' }, 404)

    if (accion === 'alta') {
      const { error } = await admin.from('mail_bajas').delete().eq('email', email)
      if (error) return json({ error: 'No se pudo guardar', detalle: error.message }, 500)
      return json({ ok: true, estado: 'alta' })
    }

    const { error } = await admin
      .from('mail_bajas')
      .upsert({ email, usuario_id: u, origen }, { onConflict: 'email', ignoreDuplicates: true })
    if (error) return json({ error: 'No se pudo guardar', detalle: error.message }, 500)
    return json({ ok: true, estado: 'baja' })
  } catch (e) {
    return json({ error: String(e) }, 500)
  }
})

// El mail de la cuenta. Si la cuenta ya no existe, el del registro del regalo
// (la baja se respeta igual si vuelve a registrarse con ese mail).
// deno-lint-ignore no-explicit-any
async function emailDe(admin: any, uid: string): Promise<string> {
  const { data: u } = await admin.from('usuarios').select('email').eq('id', uid).maybeSingle()
  if (u?.email) return String(u.email).trim().toLowerCase()
  const { data: c } = await admin.from('regalo_campana').select('email').eq('usuario_id', uid).limit(1).maybeSingle()
  if (c?.email) return String(c.email).trim().toLowerCase()
  return ''
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
