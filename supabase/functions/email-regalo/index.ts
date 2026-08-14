// Envia el mail de una gift card al destinatario via Resend.
//
// Es una función INTERNA: la llama el mp-webhook (server-side) después de que
// el pago de la gift card se aprueba y el RPC crea el regalo. Por eso NO usa el
// JWT de un usuario (x-aura-auth) sino que exige el service_role en el
// Authorization, para que nadie con la anon key pueda mandar mails de regalo.

import { corsHeaders } from '../_shared/cors.ts'

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? ''
const FROM_EMAIL =
  Deno.env.get('AURA_FROM_EMAIL') ?? 'Aura <hola@somosaurapass.com>'
const APP_URL =
  Deno.env.get('AURA_APP_URL') ?? 'https://somosauraar.netlify.app'
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    if (!RESEND_API_KEY) {
      return json({ error: 'RESEND_API_KEY no configurada en el server' }, 500)
    }

    // Guard interno: solo el backend (service_role) puede disparar este mail.
    const auth = req.headers.get('Authorization') ?? ''
    if (!SERVICE_ROLE_KEY || auth !== `Bearer ${SERVICE_ROLE_KEY}`) {
      return json({ error: 'No autorizado' }, 401)
    }

    const body = await req.json().catch(() => null)
    const {
      destinatario_email,
      codigo,
      creditos,
      remitente_nombre,
      mensaje,
    } = body ?? {}

    if (!destinatario_email || !codigo) {
      return json(
        { error: 'Faltan campos: destinatario_email, codigo' },
        400,
      )
    }

    const remitente = (typeof remitente_nombre === 'string' &&
        remitente_nombre.trim().length > 0)
      ? remitente_nombre.trim()
      : 'Alguien'
    const creditosNum = typeof creditos === 'number' && creditos > 0
      ? creditos
      : null
    const msg = typeof mensaje === 'string' && mensaje.trim().length > 0
      ? mensaje.trim()
      : null

    const html = renderHtml({
      remitente,
      codigo: String(codigo),
      creditos: creditosNum,
      mensaje: msg,
      appUrl: APP_URL,
    })

    const subject = `${remitente} te regaló créditos en Aura 🧡`
    const resendRes = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: FROM_EMAIL,
        to: String(destinatario_email).toLowerCase(),
        subject,
        html,
      }),
    })

    if (!resendRes.ok) {
      const errText = await resendRes.text()
      console.error('Resend error (email-regalo):', errText)
      return json(
        { error: 'No se pudo enviar el email', detail: errText },
        500,
      )
    }

    return json({ ok: true })
  } catch (e) {
    console.error('email-regalo exception:', e)
    return json({ error: 'Error interno' }, 500)
  }
})

function renderHtml(args: {
  remitente: string
  codigo: string
  creditos: number | null
  mensaje: string | null
  appUrl: string
}): string {
  const { remitente, codigo, creditos, mensaje, appUrl } = args

  return `<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width">
<title>Tenés un regalo en Aura</title>
</head>
<body style="font-family: -apple-system, Arial, sans-serif; background:#F7F5F2; margin:0; padding:24px;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px; margin:0 auto; background:#ffffff; border-radius:16px; overflow:hidden;">
    <tr>
      <td style="background:#1A1A1A; padding:32px 24px; text-align:center;">
        <div style="color:#E8763A; font-size:28px; font-weight:800; letter-spacing:6px;">AURA.</div>
        <div style="color:#888888; font-size:11px; margin-top:8px; letter-spacing:2px;">TE HICIERON UN REGALO</div>
      </td>
    </tr>
    <tr>
      <td style="padding:28px 24px;">
        <p style="margin:0 0 16px; color:#1A1A1A; font-size:16px; line-height:1.5;">
          <strong>${escape(remitente)}</strong> te regaló${
    creditos ? ` <strong>${creditos} créditos</strong>` : ' créditos'
  } para que uses en Aura 🧡
        </p>
        ${
    mensaje
      ? `<div style="background:#FFF1E8; border-left:3px solid #E8763A; padding:14px 16px; border-radius:8px; margin:16px 0;">
          <div style="color:#888888; font-size:11px; letter-spacing:1px; margin-bottom:6px;">SU MENSAJE</div>
          <div style="color:#1A1A1A; font-size:15px; line-height:1.5; font-style:italic;">"${escape(mensaje)}"</div>
        </div>`
      : ''
  }
        <div style="background:#F7F5F2; padding:20px 16px; border-radius:12px; margin:20px 0; text-align:center;">
          <div style="color:#888888; font-size:11px; letter-spacing:2px; margin-bottom:8px;">TU CÓDIGO</div>
          <div style="color:#E8763A; font-size:26px; font-weight:800; letter-spacing:3px;">${escape(codigo)}</div>
        </div>
        <p style="color:#555555; font-size:14px; line-height:1.6; margin:18px 0;">
          Descargá Aura, entrá con tu cuenta y canjeá este código para sumar tus
          créditos. Con ellos reservás clases en los mejores estudios de Buenos Aires.
        </p>
        <div style="text-align:center; margin:24px 0 0;">
          <a href="${escape(appUrl)}" style="display:inline-block; background:#E8763A; color:#ffffff; padding:14px 24px; border-radius:10px; text-decoration:none; font-weight:700; font-size:15px;">Canjear mi regalo</a>
        </div>
      </td>
    </tr>
    <tr>
      <td style="background:#F7F5F2; padding:16px 24px; text-align:center; color:#888888; font-size:11px;">
        Aura · el primer marketplace de fitness de Buenos Aires
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
