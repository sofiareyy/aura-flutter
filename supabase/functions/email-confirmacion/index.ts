// Envia un email de confirmacion de reserva via Resend.
// Pensado para usarse en web (donde no podemos programar notif locales),
// pero tambien sirve en mobile como respaldo.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? ''
const FROM_EMAIL =
  Deno.env.get('AURA_FROM_EMAIL') ?? 'Aura <hola@somosauraar.com>'

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    if (!RESEND_API_KEY) {
      return json({ error: 'RESEND_API_KEY no configurada en el server' }, 500)
    }

    const jwt = req.headers.get('x-aura-auth')?.trim() ?? ''
    if (!jwt) return json({ error: 'Sin autorizacion' }, 401)

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const userClient = createClient(
      supabaseUrl,
      Deno.env.get('SUPABASE_ANON_KEY')!,
    )

    const { data: { user }, error: authError } =
      await userClient.auth.getUser(jwt)
    if (authError || !user || !user.email) {
      return json({ error: 'No autorizado' }, 401)
    }

    const body = await req.json().catch(() => null)
    const {
      clase_nombre,
      estudio_nombre,
      fecha_iso,
      direccion,
      lat,
      lng,
      codigo_reserva,
    } = body ?? {}

    if (!clase_nombre || !fecha_iso || !codigo_reserva) {
      return json(
        { error: 'Faltan campos: clase_nombre, fecha_iso, codigo_reserva' },
        400,
      )
    }

    const fecha = new Date(fecha_iso)
    if (Number.isNaN(fecha.getTime())) {
      return json({ error: 'fecha_iso invalida' }, 400)
    }

    const fechaStr = fecha.toLocaleDateString('es-AR', {
      weekday: 'long',
      day: 'numeric',
      month: 'long',
      year: 'numeric',
      timeZone: 'America/Argentina/Buenos_Aires',
    })
    const horaStr = fecha.toLocaleTimeString('es-AR', {
      hour: '2-digit',
      minute: '2-digit',
      timeZone: 'America/Argentina/Buenos_Aires',
    })

    let mapsUrl: string | null = null
    if (typeof lat === 'number' && typeof lng === 'number') {
      mapsUrl =
        `https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}`
    } else if (typeof direccion === 'string' && direccion.trim().length > 0) {
      mapsUrl = `https://www.google.com/maps/search/?api=1&query=${
        encodeURIComponent(direccion)
      }`
    }

    const html = renderHtml({
      claseNombre: String(clase_nombre),
      estudioNombre: estudio_nombre ? String(estudio_nombre) : null,
      fechaStr,
      horaStr,
      direccion: direccion ? String(direccion) : null,
      mapsUrl,
      codigoReserva: String(codigo_reserva),
    })

    const resendRes = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: FROM_EMAIL,
        to: user.email,
        subject: `Reserva confirmada - ${clase_nombre}`,
        html,
      }),
    })

    if (!resendRes.ok) {
      const errText = await resendRes.text()
      console.error('Resend error:', errText)
      return json(
        { error: 'No se pudo enviar el email', detail: errText },
        500,
      )
    }

    return json({ ok: true })
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
  const {
    claseNombre,
    estudioNombre,
    fechaStr,
    horaStr,
    direccion,
    mapsUrl,
    codigoReserva,
  } = args

  return `<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width">
<title>Reserva confirmada</title>
</head>
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
          ${
        mapsUrl
          ? `<div style="margin-top:12px;"><a href="${mapsUrl}" style="display:inline-block; background:#E8763A; color:#ffffff; padding:10px 16px; border-radius:8px; text-decoration:none; font-weight:600; font-size:13px;">Abrir en Google Maps</a></div>`
          : ''
      }
        </div>`
      : ''
  }
        <div style="text-align:center; padding:18px; border:2px dashed #E8763A; border-radius:12px; margin:20px 0;">
          <div style="color:#888888; font-size:11px; text-transform:uppercase; letter-spacing:1.2px;">CODIGO DE RESERVA</div>
          <div style="color:#E8763A; font-size:22px; font-weight:800; margin-top:6px; font-family: ui-monospace, Menlo, monospace;">${escape(codigoReserva)}</div>
        </div>
        <p style="color:#555555; font-size:14px; line-height:1.6; margin:18px 0 0;">Te esperamos el <strong>${escape(fechaStr)}</strong> a las <strong>${escape(horaStr)} hs</strong>.</p>
      </td>
    </tr>
    <tr>
      <td style="background:#F7F5F2; padding:16px 24px; text-align:center; color:#888888; font-size:11px;">
        Aura - el primer marketplace de fitness de Pilar
      </td>
    </tr>
  </table>
</body>
</html>`
}

function escape(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
