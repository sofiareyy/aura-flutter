// AURA — Email al estudio cuando entra una nueva reserva.
//
// La dispara un trigger en `reservas` (via pg_net) cuando una reserva pasa a
// 'confirmada'. Manda un mail a los ADMINS del estudio (todos menos las profes,
// que tienen su aviso in-app propio). Incluye clase, día, hora y nombre del alumno.
//
// Auth: header `x-notif-secret` == NOTIF_TRIGGER_SECRET (fail-closed). No es una
// function de usuario; la llama la base.
//
// MODO TEST: si el body trae `test_email`, manda SOLO a esa casilla (ignora los
// destinatarios reales y el opt-out) — para probar sin spamear estudios reales.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? ''
const FROM_EMAIL = Deno.env.get('AURA_FROM_EMAIL') ?? 'Aura <hola@somosaurapass.com>'
const TRIGGER_SECRET = Deno.env.get('NOTIF_TRIGGER_SECRET') ?? ''

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    if (!RESEND_API_KEY) return json({ error: 'RESEND_API_KEY no configurada' }, 500)

    // Auth: solo la base (o un test autorizado) con el secreto compartido.
    if (!TRIGGER_SECRET || req.headers.get('x-notif-secret') !== TRIGGER_SECRET) {
      return json({ error: 'No autorizado' }, 401)
    }

    const body = await req.json().catch(() => null)
    const reservaId = body?.reserva_id
    const testEmail = typeof body?.test_email === 'string'
      ? body.test_email.trim().toLowerCase()
      : ''
    if (!reservaId) return json({ error: 'Falta reserva_id' }, 400)

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)

    // 1. Reserva → clase + usuario. Solo avisamos de reservas confirmadas.
    const { data: reserva } = await admin
      .from('reservas')
      .select('id, clase_id, usuario_id, estado')
      .eq('id', reservaId)
      .maybeSingle()
    if (!reserva) return json({ error: 'Reserva no encontrada' }, 404)
    // En producción solo avisamos de reservas confirmadas. En modo test (test_email)
    // ignoramos el estado: queremos probar el render/entrega con datos reales.
    if (reserva.estado !== 'confirmada' && !testEmail) {
      return json({ ok: true, skipped: 'no_confirmada', estado: reserva.estado, enviados: 0 })
    }

    // 2. Clase
    const { data: clase } = await admin
      .from('clases')
      .select('nombre, fecha, estudio_id, instructor')
      .eq('id', reserva.clase_id)
      .maybeSingle()
    if (!clase) return json({ error: 'Clase no encontrada' }, 404)

    // 3. Estudio + opt-out. `select('*')` para tolerar que la columna
    // notif_email_reservas todavía no exista (se agrega en el paso del trigger).
    const { data: estudio } = await admin
      .from('estudios')
      .select('*')
      .eq('id', clase.estudio_id)
      .maybeSingle()
    const estudioNombre = (estudio?.nombre as string | null)?.trim() || 'Tu estudio'
    const optOut = estudio?.notif_email_reservas === false
    if (optOut && !testEmail) {
      return json({ ok: true, skipped: 'opt_out', enviados: 0 })
    }

    // 4. Nombre del alumno
    const { data: alumno } = await admin
      .from('usuarios')
      .select('nombre')
      .eq('id', reserva.usuario_id)
      .maybeSingle()
    const alumnoNombre = (alumno?.nombre as string | null)?.trim() || 'Un alumno'

    // 5. Destinatarios: en test, la casilla de prueba; si no, los admins del
    // estudio EXCLUYENDO profes (rol <> 'profe').
    let destinatarios: string[]
    if (testEmail) {
      destinatarios = [testEmail]
    } else {
      const { data: admins } = await admin
        .from('estudio_admins')
        .select('usuario_id')
        .eq('estudio_id', clase.estudio_id)
        .neq('rol', 'profe')
      const emails: string[] = []
      for (const a of admins ?? []) {
        const { data: u } = await admin.auth.admin.getUserById(a.usuario_id as string)
        const email = u?.user?.email?.trim().toLowerCase()
        if (email && email.includes('@')) emails.push(email)
      }
      destinatarios = [...new Set(emails)]
    }
    if (destinatarios.length === 0) {
      return json({ ok: true, enviados: 0, motivo: 'sin_destinatarios' })
    }

    // 6. Fecha / hora en horario de Argentina
    // `clases.fecha` es `timestamp without time zone` con la hora de pared de
    // Argentina (ej. 18:00), sin zona. El cliente la recibe como
    // "2026-06-12T18:00:00" y Deno la parsea como UTC. La formateamos en UTC
    // para conservar esa hora de pared: si usáramos la tz de Argentina, restaría
    // 3h de más y mostraría 15:00. 24h + "hs" (sin am/pm).
    const fecha = clase.fecha ? new Date(String(clase.fecha)) : null
    const valid = !!fecha && !Number.isNaN(fecha.getTime())
    const fechaStr = valid
      ? fecha!.toLocaleDateString('es-AR', {
        weekday: 'long', day: 'numeric', month: 'long', timeZone: 'UTC',
      })
      : null
    const horaStr = valid
      ? fecha!.toLocaleTimeString('es-AR', {
        hour: '2-digit', minute: '2-digit', hour12: false, timeZone: 'UTC',
      })
      : null
    const claseNombre = (clase.nombre as string | null)?.trim() || 'tu clase'
    const instructorNombre = (clase.instructor as string | null)?.trim() || ''

    const subject = horaStr
      ? `Nueva reserva en ${estudioNombre} — ${claseNombre} ${horaStr}`
      : `Nueva reserva en ${estudioNombre} — ${claseNombre}`
    const html = renderHtml({ estudioNombre, claseNombre, instructorNombre, alumnoNombre, fechaStr, horaStr })

    // 7. Enviar por Resend. El `to` son los admins del estudio (en test, la
    // casilla de prueba) — NUNCA la propia dirección de Aura. Son co-managers
    // del mismo estudio, así que se pueden ver entre sí sin problema.
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ from: FROM_EMAIL, reply_to: 'aura.hola.app@gmail.com', to: destinatarios, subject, html }),
    })

    if (!res.ok) {
      const detail = await res.text()
      console.error('Resend error:', detail)
      return json({ ok: false, error: 'resend_error', detail }, 502)
    }
    const out = await res.json().catch(() => ({}))
    return json({
      ok: true,
      enviados: destinatarios.length,
      test: !!testEmail,
      resend_id: (out as { id?: string })?.id,
    })
  } catch (e) {
    console.error('nueva-reserva-estudio-email exception:', e)
    return json({ error: 'Error interno' }, 500)
  }
})

function renderHtml(args: {
  estudioNombre: string
  claseNombre: string
  instructorNombre: string
  alumnoNombre: string
  fechaStr: string | null
  horaStr: string | null
}): string {
  const { estudioNombre, claseNombre, instructorNombre, alumnoNombre, fechaStr, horaStr } = args
  const cuando = fechaStr && horaStr
    ? `${escape(fechaStr)} a las ${escape(horaStr)} hs`
    : (fechaStr ? escape(fechaStr) : '')
  return `<!doctype html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Nueva reserva</title></head>
<body style="font-family:-apple-system,Arial,sans-serif; background:#F7F5F2; margin:0; padding:24px;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px; margin:0 auto; background:#fff; border-radius:16px; overflow:hidden;">
    <tr><td style="background:#1A1A1A; padding:32px 24px; text-align:center;">
      <div style="color:#E8763A; font-size:28px; font-weight:800; letter-spacing:6px;">AURA.</div>
      <div style="color:#888; font-size:11px; margin-top:8px; letter-spacing:2px;">NUEVA RESERVA</div>
    </td></tr>
    <tr><td style="padding:28px 24px;">
      <p style="margin:0 0 16px; color:#1A1A1A; font-size:16px; line-height:1.5;">
        Tenés una nueva reserva en <strong>${escape(estudioNombre)}</strong> 🧡
      </p>
      <div style="background:#FFF1E8; border-left:4px solid #E8763A; padding:16px; border-radius:8px; margin:16px 0; color:#1A1A1A; font-size:15px; line-height:1.8;">
        🧘 <strong>Clase:</strong> ${escape(claseNombre)}<br>
        ${instructorNombre ? `🧑‍🏫 <strong>Profe:</strong> ${escape(instructorNombre)}<br>` : ''}
        ${cuando ? `📅 <strong>Cuándo:</strong> ${cuando}<br>` : ''}
        👤 <strong>Alumno:</strong> ${escape(alumnoNombre)}
      </div>
      <p style="margin:16px 0 0; color:#555; font-size:14px;">Podés ver la lista completa de asistentes en la app.</p>
    </td></tr>
    <tr><td style="background:#F7F5F2; padding:16px 24px; text-align:center; color:#888; font-size:11px;">
      Recibís este mail porque administrás este estudio en Aura.
    </td></tr>
  </table>
</body></html>`
}

function escape(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}
