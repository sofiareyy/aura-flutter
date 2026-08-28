// Mail de confirmación de reserva a la ALUMNA.
//
// 2026-08-29: refactorizada al patrón de los otros mails (nueva-reserva-
// estudio-email, resena-email): la dispara la BASE por pg_net cuando la
// reserva queda confirmada, con el secreto compartido. Antes esperaba el JWT
// de la alumna (x-aura-auth) y que la app la llamara — nunca se cableó ni se
// desplegó. Ahora recibe reserva_id y resuelve todo server-side.
//
// Auth: header `x-notif-secret` == NOTIF_TRIGGER_SECRET (fail-closed).
// MODO TEST: `test_email` en el body manda SOLO a esa casilla (e ignora el
// estado de la reserva, para poder probar con una completada real).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? ''
const FROM_EMAIL = Deno.env.get('AURA_FROM_EMAIL') ?? 'Aura <hola@somosaurapass.com>'
const TRIGGER_SECRET = Deno.env.get('NOTIF_TRIGGER_SECRET') ?? ''

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  try {
    if (!RESEND_API_KEY) return json({ error: 'RESEND_API_KEY no configurada' }, 500)
    if (!TRIGGER_SECRET || req.headers.get('x-notif-secret') !== TRIGGER_SECRET) {
      return json({ error: 'No autorizado' }, 401)
    }

    const body = await req.json().catch(() => null)
    const reservaId = Number(body?.reserva_id)
    const testEmail = typeof body?.test_email === 'string'
      ? body.test_email.trim().toLowerCase() : ''
    if (!reservaId) return json({ error: 'Falta reserva_id' }, 400)

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)

    const { data: r } = await admin
      .from('reservas')
      .select('id, usuario_id, clase_id, estado, codigo_qr')
      .eq('id', reservaId)
      .maybeSingle()
    if (!r) return json({ error: 'Reserva no encontrada' }, 404)
    if (r.estado !== 'confirmada' && !testEmail) {
      return json({ ok: true, skipped: 'no_confirmada', estado: r.estado, enviados: 0 })
    }

    const { data: clase } = await admin
      .from('clases')
      .select('nombre, fecha, estudio_id')
      .eq('id', r.clase_id)
      .maybeSingle()
    if (!clase) return json({ error: 'Clase no encontrada' }, 404)

    const { data: estudio } = await admin
      .from('estudios')
      .select('nombre, direccion, lat, lng')
      .eq('id', clase.estudio_id)
      .maybeSingle()

    // El mail de la alumna, del lado del server. Lápidas no reciben nada.
    let email = testEmail
    if (!email) {
      const { data: u } = await admin.auth.admin.getUserById(String(r.usuario_id))
      email = u?.user?.email?.trim().toLowerCase() ?? ''
    }
    if (!email || !email.includes('@') || email.endsWith('@cuenta-eliminada.aura')) {
      return json({ ok: true, enviados: 0, motivo: 'sin_email' })
    }

    // `clases.fecha` es timestamp SIN zona con hora de pared argentina. Deno
    // parsea el string como UTC; formatear en UTC devuelve la hora de pared
    // tal cual (mismo criterio medido en nueva-reserva-estudio-email).
    const fecha = new Date(String(clase.fecha))
    if (Number.isNaN(fecha.getTime())) return json({ error: 'fecha inválida' }, 400)
    const fechaStr = fecha.toLocaleDateString('es-AR', {
      weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC',
    })
    const horaStr = fecha.toLocaleTimeString('es-AR', {
      hour: '2-digit', minute: '2-digit', timeZone: 'UTC',
    })

    const direccion = (estudio?.direccion as string | null)?.trim() || null
    const lat = estudio?.lat, lng = estudio?.lng
    let mapsUrl: string | null = null
    if (typeof lat === 'number' && typeof lng === 'number') {
      mapsUrl = `https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}`
    } else if (direccion) {
      mapsUrl = `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(direccion)}`
    }

    // El identificador corto, el mismo que muestra la app (#BK-<bloque hex>).
    // QR nuevo: AURA-<8hex>-<clase>-<ms>-<4dig> => el hex. Viejo: entero.
    const qr = String(r.codigo_qr ?? '')
    const partes = qr.split('-')
    const codigoCorto = (partes.length >= 2 && partes[1]) ? `#BK-${partes[1]}` : qr

    const html = renderHtml({
      claseNombre: String(clase.nombre ?? 'Tu clase'),
      estudioNombre: (estudio?.nombre as string | null) ?? null,
      fechaStr, horaStr, direccion, mapsUrl,
      codigoReserva: codigoCorto,
    })

    const resendRes = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: FROM_EMAIL,
        reply_to: 'aura.hola.app@gmail.com',
        to: email,
        subject: `Reserva confirmada - ${clase.nombre ?? 'tu clase'}`,
        html,
      }),
    })
    if (!resendRes.ok) {
      const errText = await resendRes.text()
      console.error('Resend error:', errText)
      return json({ error: 'No se pudo enviar el email', detail: errText }, 502)
    }
    const out = await resendRes.json().catch(() => ({}))
    return json({ ok: true, enviados: 1, resend_id: (out as { id?: string })?.id })
  } catch (e) {
    console.error('email-confirmacion exception:', e)
    return json({ error: 'Error interno' }, 500)
  }
})

function renderHtml(args: {
  claseNombre: string
  estudioNombre: string | null
  fechaStr: string
  horaStr: string
  direccion: string | null
  mapsUrl: string | null
  codigoReserva: string
}): string {
  const { claseNombre, estudioNombre, fechaStr, horaStr, direccion, mapsUrl, codigoReserva } = args
  return `<!doctype html>
<html lang="es">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Reserva confirmada</title></head>
<body style="font-family: -apple-system, Arial, sans-serif; background:#F7F5F2; margin:0; padding:24px;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px; margin:0 auto; background:#ffffff; border-radius:16px; overflow:hidden;">
    <tr>
      <td style="background:#1A1A1A; padding:32px 24px; text-align:center;">
        <div style="color:#E8763A; font-size:28px; font-weight:800; letter-spacing:6px;">AURA.</div>
        <div style="color:#888888; font-size:11px; margin-top:8px; letter-spacing:2px;">RESERVA CONFIRMADA</div>
      </td>
    </tr>
    <tr>
      <td style="padding:28px 24px;">
        <h2 style="margin:0 0 6px; color:#1A1A1A; font-size:22px;">${escape(claseNombre)}</h2>
        ${estudioNombre ? `<p style="margin:0 0 16px; color:#888888; font-size:14px;">${escape(estudioNombre)}</p>` : ''}
        <div style="background:#F7F5F2; padding:16px; border-radius:12px; margin:16px 0;">
          <div style="color:#888888; font-size:11px; text-transform:uppercase; letter-spacing:1.2px;">CUANDO</div>
          <div style="color:#1A1A1A; font-size:16px; font-weight:600; margin-top:6px;">${escape(fechaStr)}</div>
          <div style="color:#1A1A1A; font-size:14px; margin-top:4px;">${escape(horaStr)} hs</div>
        </div>
        ${
    direccion
      ? `<div style="background:#F7F5F2; padding:16px; border-radius:12px; margin:16px 0;">
          <div style="color:#888888; font-size:11px; text-transform:uppercase; letter-spacing:1.2px;">DONDE</div>
          <div style="color:#1A1A1A; font-size:14px; margin-top:6px;">${escape(direccion)}</div>
          ${mapsUrl ? `<div style="margin-top:12px;"><a href="${mapsUrl}" style="display:inline-block; background:#E8763A; color:#ffffff; padding:10px 16px; border-radius:8px; text-decoration:none; font-weight:600; font-size:13px;">Abrir en Google Maps</a></div>` : ''}
        </div>`
      : ''
  }
        <div style="text-align:center; padding:18px; border:2px dashed #E8763A; border-radius:12px; margin:20px 0;">
          <div style="color:#888888; font-size:11px; text-transform:uppercase; letter-spacing:1.2px;">CODIGO DE RESERVA</div>
          <div style="color:#E8763A; font-size:22px; font-weight:800; margin-top:6px; font-family: ui-monospace, Menlo, monospace;">${escape(codigoReserva)}</div>
        </div>
        <p style="color:#555555; font-size:14px; line-height:1.6; margin:0 0 6px; text-align:center;">Mostrá este código al llegar para registrar tu asistencia.</p>
        <p style="color:#555555; font-size:14px; line-height:1.6; margin:18px 0 0;">Te esperamos el <strong>${escape(fechaStr)}</strong> a las <strong>${escape(horaStr)} hs</strong>.</p>
      </td>
    </tr>
    <tr>
      <td style="background:#F7F5F2; padding:16px 24px; text-align:center; color:#888888; font-size:11px;">
        Aura - el primer marketplace de fitness y experiencias de Buenos Aires
      </td>
    </tr>
  </table>
</body>
</html>`
}

function escape(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
          .replace(/"/g, '&quot;').replace(/'/g, '&#39;')
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
