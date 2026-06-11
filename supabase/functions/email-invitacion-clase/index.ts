// Envia un email de invitacion a una clase via Resend.
// Se invoca desde el flujo "Invitar amigas" en DetalleClaseScreen.
// A diferencia de email-confirmacion (que manda a la propia user.email),
// aca el destinatario lo elige el invitador y se manda al invitado.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? ''
const FROM_EMAIL =
  Deno.env.get('AURA_FROM_EMAIL') ?? 'Aura <hola@somosauraar.com>'
const APP_URL =
  Deno.env.get('AURA_APP_URL') ?? 'https://somosauraar.netlify.app'

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
    if (authError || !user) return json({ error: 'No autorizado' }, 401)

    const body = await req.json().catch(() => null)
    const {
      invitado_email,
      invitador_nombre,
      clase_nombre,
      estudio_nombre,
      fecha_iso,
      direccion,
    } = body ?? {}

    if (!invitado_email || !clase_nombre || !fecha_iso) {
      return json(
        {
          error:
            'Faltan campos: invitado_email, clase_nombre, fecha_iso',
        },
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
      timeZone: 'America/Argentina/Buenos_Aires',
    })
    const horaStr = fecha.toLocaleTimeString('es-AR', {
      hour: '2-digit',
      minute: '2-digit',
      timeZone: 'America/Argentina/Buenos_Aires',
    })

    const invitador = (typeof invitador_nombre === 'string' &&
        invitador_nombre.trim().length > 0)
      ? invitador_nombre.trim()
      : 'Una amiga'
    const estudio = typeof estudio_nombre === 'string' && estudio_nombre.trim()
      ? estudio_nombre.trim()
      : null
    const dir = typeof direccion === 'string' && direccion.trim()
      ? direccion.trim()
      : null

    const html = renderHtml({
      invitador,
      claseNombre: String(clase_nombre),
      estudioNombre: estudio,
      fechaStr,
      horaStr,
      direccion: dir,
      appUrl: APP_URL,
    })

    const subject = `${invitador} te invitó a una clase en Aura`
    const resendRes = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: FROM_EMAIL,
        to: String(invitado_email).toLowerCase(),
        subject,
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
    console.error('email-invitacion-clase exception:', e)
    return json({ error: 'Error interno' }, 500)
  }
})

function renderHtml(args: {
  invitador: string
  claseNombre: string
  estudioNombre: string | null
  fechaStr: string
  horaStr: string
  direccion: string | null
  appUrl: string
}): string {
  const {
    invitador,
    claseNombre,
    estudioNombre,
    fechaStr,
    horaStr,
    direccion,
    appUrl,
  } = args

  return `<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width">
<title>Tenes una invitacion</title>
</head>
<body style="font-family: -apple-system, Arial, sans-serif; background:#F7F5F2; margin:0; padding:24px;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px; margin:0 auto; background:#ffffff; border-radius:16px; overflow:hidden;">
    <tr>
      <td style="background:#1A1A1A; padding:32px 24px; text-align:center;">
        <div style="color:#E8763A; font-size:28px; font-weight:800; letter-spacing:6px;">AURA.</div>
        <div style="color:#888888; font-size:11px; margin-top:8px; letter-spacing:2px;">TE INVITARON A UNA CLASE</div>
      </td>
    </tr>
    <tr>
      <td style="padding:28px 24px;">
        <p style="margin:0 0 16px; color:#1A1A1A; font-size:16px; line-height:1.5;">
          <strong>${escape(invitador)}</strong> te invito a
          <strong>${escape(claseNombre)}</strong>${
    estudioNombre ? ` en <strong>${escape(estudioNombre)}</strong>` : ''
  }.
        </p>
        <div style="background:#F7F5F2; padding:16px; border-radius:12px; margin:16px 0;">
          <div style="color:#1A1A1A; font-size:15px; margin:4px 0;">📅 ${escape(fechaStr)} a las ${escape(horaStr)} hs</div>
          ${
    direccion
      ? `<div style="color:#1A1A1A; font-size:15px; margin:4px 0;">📍 ${escape(direccion)}</div>`
      : ''
  }
        </div>
        <p style="color:#555555; font-size:14px; line-height:1.6; margin:18px 0;">Descarga Aura y reserva tu lugar antes de que se llene.</p>
        <div style="text-align:center; margin:24px 0 0;">
          <a href="${escape(appUrl)}" style="display:inline-block; background:#E8763A; color:#ffffff; padding:14px 24px; border-radius:10px; text-decoration:none; font-weight:700; font-size:15px;">Abrir Aura</a>
        </div>
      </td>
    </tr>
    <tr>
      <td style="background:#F7F5F2; padding:16px 24px; text-align:center; color:#888888; font-size:11px;">
        Aura - el primer marketplace de fitness de Buenos Aires
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
