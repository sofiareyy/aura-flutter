// AURA — FIX 7: email de respaldo para los avisos del estudio.
//
// Problema: los avisos que manda el estudio ("la clase se cancela", "cambio
// de sala") se insertan en `notificaciones_usuario` y solo se ven cuando la
// alumna abre la app. No hay push remoto, asi que un aviso urgente puede
// llegar tarde o no llegar.
//
// Mientras no exista FCM, el email es el canal de respaldo. Se manda SOLO
// para avisos de tipo 'urgente': el ruido de mandar un mail por cada aviso
// general haria que dejen de leerlos.
//
// Seguridad: se exige el JWT del estudio (header x-aura-auth) y se verifica
// contra `estudio_admins` que quien llama administre el estudio duenio de la
// clase. Sin ese chequeo, cualquier usuario autenticado podria disparar
// mails masivos a los alumnos de cualquier clase.
//
// Preferencias: solo reciben mail las usuarias con `notifs_reservas = true`.
// La notificacion in-app se sigue insertando para todas (la hace el cliente,
// no esta funcion): es pasiva y vive dentro de la app que ya usan, asi que
// silenciarla podria ocultarles que su clase se cancelo.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? ''
const FROM_EMAIL = Deno.env.get('AURA_FROM_EMAIL') ??
  'Aura <hola@somosaurapass.com>'
const APP_URL = Deno.env.get('AURA_APP_URL') ??
  'https://sofiareyy.github.io/aura-flutter'

// Resend acepta hasta 50 destinatarios por request.
const BATCH_SIZE = 50

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    if (!RESEND_API_KEY) {
      return json({ error: 'RESEND_API_KEY no configurada' }, 500)
    }

    const jwt = req.headers.get('x-aura-auth')?.trim() ?? ''
    if (!jwt) return json({ error: 'Sin autorizacion' }, 401)

    const userClient = createClient(SUPABASE_URL, ANON_KEY)
    const { data: { user }, error: authError } = await userClient.auth.getUser(
      jwt,
    )
    if (authError || !user) return json({ error: 'No autorizado' }, 401)

    const body = await req.json().catch(() => null)
    const { aviso_id } = body ?? {}

    if (!aviso_id) {
      return json({ error: 'Falta aviso_id' }, 400)
    }

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)

    // ── 1. El envio, con su estudio y sus clases ─────────────────────────
    const { data: aviso, error: avisoErr } = await admin
      .from('avisos_envios')
      .select('id, estudio_id, tipo, mensaje, clase_ids, estudios(nombre)')
      .eq('id', aviso_id)
      .maybeSingle()

    if (avisoErr || !aviso) {
      return json({ error: 'Aviso no encontrado' }, 404)
    }

    // Solo los urgentes mandan mail: uno por cada aviso general haria que
    // dejen de leerlos, y entonces el urgente tampoco llega.
    if (aviso.tipo !== 'urgente') {
      return json({ ok: true, skipped: 'no_urgente', enviados: 0 })
    }

    // ── 2. Autorizacion: el caller administra ese estudio ────────────────
    const { data: esAdmin } = await admin
      .from('estudio_admins')
      .select('id')
      .eq('estudio_id', aviso.estudio_id)
      .eq('usuario_id', user.id)
      .maybeSingle()

    if (!esAdmin) {
      return json({ error: 'No administras este estudio' }, 403)
    }

    // ── 3. Destinatarios ────────────────────────────────────────────────
    // El RPC ya resolvio dedup, tope diario y preferencias: aca solo
    // leemos a quien le corresponde canal email.
    const { data: filas } = await admin.rpc('aviso_destinatarios_email', {
      p_aviso_id: aviso_id,
    })

    const destinatarios = [
      ...new Set(
        (filas ?? [])
          .map((f: { email: string }) => f.email?.trim().toLowerCase())
          .filter((e: string) => !!e && e.includes('@')),
      ),
    ] as string[]

    if (destinatarios.length === 0) {
      return json({ ok: true, enviados: 0, motivo: 'sin_destinatarios' })
    }

    // Fecha de la primera clase del envio, solo para el cuerpo del mail.
    const claseIds = (aviso.clase_ids ?? []) as number[]
    const { data: clases } = await admin
      .from('clases')
      .select('nombre, fecha')
      .in('id', claseIds.length > 0 ? claseIds : [-1])
      .order('fecha', { ascending: true })
      .limit(1)

    const primera = (clases ?? [])[0]
    const mensaje = String(aviso.mensaje ?? '')

    // ── 4. Armar y mandar ────────────────────────────────────────────────
    const estudioNombre =
      (aviso.estudios as { nombre?: string } | null)?.nombre?.trim() ||
      'Tu estudio'
    const claseNombre = (primera?.nombre as string | null)?.trim() ||
      'tus clases'

    const fecha = primera?.fecha ? new Date(String(primera.fecha)) : null
    const fechaStr = fecha && !Number.isNaN(fecha.getTime())
      ? fecha.toLocaleDateString('es-AR', {
        weekday: 'long',
        day: 'numeric',
        month: 'long',
        timeZone: 'America/Argentina/Buenos_Aires',
      })
      : null
    const horaStr = fecha && !Number.isNaN(fecha.getTime())
      ? fecha.toLocaleTimeString('es-AR', {
        hour: '2-digit',
        minute: '2-digit',
        timeZone: 'America/Argentina/Buenos_Aires',
      })
      : null

    // El asunto lleva el mensaje recortado como titulo, que es lo que la
    // alumna necesita ver desde la bandeja sin abrir el mail.
    const titulo = mensaje.trim().length > 60
      ? `${mensaje.trim().slice(0, 57)}...`
      : mensaje.trim()
    const subject = `Aviso de ${estudioNombre}: ${titulo}`

    const html = renderHtml({
      estudioNombre,
      claseNombre,
      mensaje: mensaje.trim(),
      fechaStr,
      horaStr,
      appUrl: APP_URL,
    })

    let enviados = 0
    const errores: string[] = []

    for (let i = 0; i < destinatarios.length; i += BATCH_SIZE) {
      const lote = destinatarios.slice(i, i + BATCH_SIZE)
      const res = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${RESEND_API_KEY}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          from: FROM_EMAIL,
        reply_to: 'aura.hola.app@gmail.com',
          // `bcc` para que las alumnas no vean los mails de las demas.
          to: FROM_EMAIL,
          bcc: lote,
          subject,
          html,
        }),
      })

      if (res.ok) {
        enviados += lote.length
      } else {
        const detail = await res.text()
        console.error('Resend error:', detail)
        errores.push(detail)
      }
    }

    return json({
      ok: errores.length === 0,
      enviados,
      errores: errores.length > 0 ? errores : undefined,
    })
  } catch (e) {
    console.error('aviso-alumnos-email exception:', e)
    return json({ error: 'Error interno' }, 500)
  }
})

function renderHtml(args: {
  estudioNombre: string
  claseNombre: string
  mensaje: string
  fechaStr: string | null
  horaStr: string | null
  appUrl: string
}): string {
  const { estudioNombre, claseNombre, mensaje, fechaStr, horaStr, appUrl } =
    args

  const cuando = fechaStr && horaStr
    ? `<div style="color:#1A1A1A; font-size:15px; margin:4px 0;">📅 ${
      escape(fechaStr)
    } a las ${escape(horaStr)} hs</div>`
    : ''

  return `<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width">
<title>Aviso de ${escape(estudioNombre)}</title>
</head>
<body style="font-family: -apple-system, Arial, sans-serif; background:#F7F5F2; margin:0; padding:24px;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px; margin:0 auto; background:#ffffff; border-radius:16px; overflow:hidden;">
    <tr>
      <td style="background:#1A1A1A; padding:32px 24px; text-align:center;">
        <div style="color:#E8763A; font-size:28px; font-weight:800; letter-spacing:6px;">AURA.</div>
        <div style="color:#888888; font-size:11px; margin-top:8px; letter-spacing:2px;">AVISO IMPORTANTE</div>
      </td>
    </tr>
    <tr>
      <td style="padding:28px 24px;">
        <p style="margin:0 0 16px; color:#1A1A1A; font-size:16px; line-height:1.5;">
          <strong>${escape(estudioNombre)}</strong> te manda un aviso sobre
          <strong>${escape(claseNombre)}</strong>:
        </p>
        <div style="background:#FFF1E8; border-left:4px solid #E8763A; padding:16px; border-radius:8px; margin:16px 0;">
          <div style="color:#1A1A1A; font-size:16px; line-height:1.5;">${
    escape(mensaje)
  }</div>
        </div>
        ${
    cuando
      ? `<div style="background:#F7F5F2; padding:16px; border-radius:12px; margin:16px 0;">${cuando}</div>`
      : ''
  }
        <div style="text-align:center; margin:24px 0 0;">
          <a href="${
    escape(appUrl)
  }" style="display:inline-block; background:#E8763A; color:#ffffff; padding:14px 24px; border-radius:10px; text-decoration:none; font-weight:700; font-size:15px;">Abrir Aura</a>
        </div>
      </td>
    </tr>
    <tr>
      <td style="background:#F7F5F2; padding:16px 24px; text-align:center; color:#888888; font-size:11px;">
        Recibis este mail porque tenes una reserva en esta clase.<br>
        Podes desactivarlo en Aura &gt; Perfil &gt; Notificaciones.
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
