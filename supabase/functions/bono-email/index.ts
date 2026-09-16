// Mail del BONO DE BIENVENIDA a la usuaria.
//
// La dispara la BASE por pg_net desde `acreditar_bono`, con el secreto
// compartido — mismo patrón que email-confirmacion, cancelacion-email y
// resena-email. Recibe user_id y resuelve todo server-side.
//
// Auth: header `x-notif-secret` == NOTIF_TRIGGER_SECRET (fail-closed).
// MODO TEST: `test_email` en el body manda SOLO a esa casilla, sin tocar a
// nadie real. Es la forma de probar la plantilla antes de prender el bono.
//
// Por qué mail y no sólo push: medido el 14/9/2026, de las 79 usuarias que
// nunca compraron un pack sólo 13 tienen push (iPhone con la app instalada).
// El mail es el único canal que llega a las que no abren la app — que son
// justo las que el bono tiene que despertar.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? ''
const FROM_EMAIL = Deno.env.get('AURA_FROM_EMAIL') ?? 'Aura <hola@somosaurapass.com>'
const TRIGGER_SECRET = Deno.env.get('NOTIF_TRIGGER_SECRET') ?? ''

const WEB = 'https://somosaurapass.com'

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  try {
    if (!RESEND_API_KEY) return json({ error: 'RESEND_API_KEY no configurada' }, 500)
    if (!TRIGGER_SECRET || req.headers.get('x-notif-secret') !== TRIGGER_SECRET) {
      return json({ error: 'No autorizado' }, 401)
    }

    const body = await req.json().catch(() => null)
    const userId = typeof body?.user_id === 'string' ? body.user_id.trim() : ''
    const testEmail = typeof body?.test_email === 'string'
      ? body.test_email.trim().toLowerCase() : ''
    // `kind`: 'otorgado' (recién acreditado) o 'recordatorio' (sigue sin usarlo).
    const kind = body?.kind === 'recordatorio' ? 'recordatorio' : 'otorgado'
    if (!userId && !testEmail) return json({ error: 'Falta user_id' }, 400)

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)

    let nombre = 'Hola'
    let email = testEmail
    let monto = 16
    let restante = 16
    let venceEl: string | null = null

    if (userId) {
      const { data: u } = await admin
        .from('usuarios')
        .select('nombre, email')
        .eq('id', userId)
        .maybeSingle()
      if (!u && !testEmail) return json({ error: 'Usuaria no encontrada' }, 404)
      if (u?.nombre) nombre = String(u.nombre).split(' ')[0]
      if (!testEmail) email = String(u?.email ?? '').trim().toLowerCase()

      // El lote del bono: cuánto le dieron, cuánto le queda y cuándo vence.
      const { data: lote } = await admin
        .from('creditos_movimientos')
        .select('amount_total, amount_remaining, expires_at')
        .eq('user_id', userId)
        .eq('source', 'bono_bienvenida')
        .order('id', { ascending: false })
        .limit(1)
        .maybeSingle()
      if (lote) {
        monto = Number(lote.amount_total ?? monto)
        restante = Number(lote.amount_remaining ?? monto)
        venceEl = lote.expires_at ?? null
      }
      // Ya lo usó entero: no tiene sentido recordarle nada.
      if (kind === 'recordatorio' && restante <= 0 && !testEmail) {
        return json({ ok: true, skipped: 'ya_usado', enviados: 0 })
      }
    }

    if (!email) return json({ error: 'Sin email' }, 400)

    const vence = venceEl ? fechaLarga(venceEl) : null
    const asunto = kind === 'recordatorio'
      ? `${nombre}, te quedan ${restante} créditos sin usar`
      : `${nombre}, te regalamos ${monto} créditos 🧡`

    const resendRes = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: FROM_EMAIL,
        reply_to: 'aura.hola.app@gmail.com',
        to: email,
        subject: asunto,
        html: renderHtml({ nombre, monto, restante, vence, kind }),
      }),
    })
    if (!resendRes.ok) {
      const errText = await resendRes.text()
      return json({ error: 'resend_fallo', detalle: errText.slice(0, 300) }, 502)
    }
    const out = await resendRes.json().catch(() => ({}))
    return json({ ok: true, enviados: 1, resend_id: (out as { id?: string })?.id })
  } catch (e) {
    return json({ error: String(e) }, 500)
  }
})

function fechaLarga(iso: string): string {
  try {
    const d = new Date(iso + (iso.length === 10 ? 'T12:00:00Z' : ''))
    return d.toLocaleDateString('es-AR', {
      day: 'numeric', month: 'long', timeZone: 'America/Argentina/Buenos_Aires',
    })
  } catch (_) {
    return iso
  }
}

function renderHtml(
  p: { nombre: string; monto: number; restante: number; vence: string | null; kind: string },
): string {
  const titulo = p.kind === 'recordatorio'
    ? `Todavía tenés ${p.restante} créditos`
    : `Te regalamos ${p.monto} créditos`
  const bajada = p.kind === 'recordatorio'
    ? 'Están en tu cuenta esperándote. Alcanzan para una clase.'
    : 'Son tuyos, ya están en tu cuenta. Alcanzan para una clase.'
  const aviso = p.vence
    ? `<p style="margin:0 0 24px;color:#B8B0A9;font-size:14px;line-height:1.5">
         Los podés usar hasta el <strong style="color:#F5F0E8">${p.vence}</strong>.
       </p>`
    : ''
  return `<!doctype html>
<html lang="es"><body style="margin:0;padding:0;background:#0D0D0D">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#0D0D0D;padding:32px 16px">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;background:#1A1A1A;border-radius:20px;padding:32px">
        <tr><td>
          <p style="margin:0 0 24px;color:#E8763A;font-size:15px;font-weight:800;letter-spacing:4px">AURA.</p>
          <h1 style="margin:0 0 12px;color:#F5F0E8;font-size:26px;line-height:1.25;font-family:Arial,sans-serif">
            ${p.nombre}, ${titulo} 🧡
          </h1>
          <p style="margin:0 0 20px;color:#B8B0A9;font-size:15px;line-height:1.6;font-family:Arial,sans-serif">
            ${bajada} Elegí el estudio que quieras —pilates, yoga, spinning, cerámica— y reservá tu lugar.
          </p>
          ${aviso}
          <a href="${WEB}/#/explorar"
             style="display:inline-block;background:#E8763A;color:#fff;text-decoration:none;
                    padding:14px 28px;border-radius:12px;font-weight:700;font-size:15px;font-family:Arial,sans-serif">
            Ver clases
          </a>
          <p style="margin:28px 0 0;color:#6E6761;font-size:12px;line-height:1.5;font-family:Arial,sans-serif">
            Te escribimos porque tenés una cuenta en Aura y estos créditos están en ella.
            Si no querés volver a recibir avisos como este, respondé este mail y te sacamos.
          </p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
