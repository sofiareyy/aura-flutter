// Mail de CLASE CANCELADA por el estudio.
//
// Lo dispara la base al final de `estudio_cancelar_clase`, vía pg_net, con el
// mismo secreto compartido que los otros mails (fail-closed).
//
// ⚠️ ES EL PRIMER MAIL EN LOTE: cancelar una clase con 12 anotadas manda 12
// mails. Por eso:
//   · La base hace UNA sola llamada con `clase_id`; el loop vive acá, donde se
//     puede manejar un fallo parcial sin dejar la cancelación a medias.
//   · Se manda UN MAIL POR PERSONA, nunca uno con 12 destinatarios: eso
//     filtraría el mail de cada alumna al resto.
//   · Un fallo individual no corta el lote: se cuenta y se sigue.
//
// MODO PRUEBA: `dry_run: true` arma todo y devuelve a quién le escribiría, sin
// mandar un solo mail. `test_email` manda el lote entero a esa casilla.

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
    if (!TRIGGER_SECRET || req.headers.get('x-notif-secret') !== TRIGGER_SECRET) {
      return json({ error: 'No autorizado' }, 401)
    }
    const body = await req.json().catch(() => null)
    const claseId = Number(body?.clase_id)
    if (!claseId) return json({ error: 'Falta clase_id' }, 400)

    const dryRun = body?.dry_run === true
    const testEmail = typeof body?.test_email === 'string'
      ? body.test_email.trim().toLowerCase() : ''
    if (!RESEND_API_KEY && !dryRun) {
      return json({ error: 'RESEND_API_KEY no configurada' }, 500)
    }

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)

    const { data: clase } = await admin
      .from('clases')
      .select('id, nombre, fecha, tipo, estudio_id')
      .eq('id', claseId)
      .maybeSingle()
    if (!clase) return json({ error: 'Clase no encontrada' }, 404)

    const { data: estudio } = await admin
      .from('estudios').select('nombre').eq('id', clase.estudio_id).maybeSingle()
    const estudioNombre = (estudio?.nombre as string | null)?.trim() || 'el estudio'
    const esExperiencia = clase.tipo === 'workshop'

    // Las reservas que la cancelación acaba de tumbar. `usuario_id` puede ser
    // NULL: reserva de una cuenta borrada, conservada como evidencia de cobro.
    const { data: reservas } = await admin
      .from('reservas')
      .select('id, usuario_id, creditos_usados')
      .eq('clase_id', claseId)
      .eq('estado', 'cancelada_por_estudio')

    const { fechaStr, horaStr } = formatearFecha(String(clase.fecha ?? ''))

    const resultados: Array<Record<string, unknown>> = []
    let enviados = 0
    let fallidos = 0

    for (const r of reservas ?? []) {
      if (!r.usuario_id) {
        resultados.push({ reserva: r.id, saltada: 'cuenta_borrada' })
        continue
      }
      let email = testEmail
      let nombre = ''
      const { data: u } = await admin
        .from('usuarios').select('nombre, rol').eq('id', r.usuario_id).maybeSingle()
      nombre = (u?.nombre as string | null)?.trim().split(' ')[0] ?? ''
      if (u?.rol === 'eliminado') {
        resultados.push({ reserva: r.id, saltada: 'cuenta_eliminada' })
        continue
      }
      if (!email) {
        const { data: au } = await admin.auth.admin.getUserById(String(r.usuario_id))
        email = au?.user?.email?.trim().toLowerCase() ?? ''
      }
      if (!email || !email.includes('@') || email.endsWith('@cuenta-eliminada.aura')) {
        resultados.push({ reserva: r.id, saltada: 'sin_email' })
        continue
      }

      const creditos = Number(r.creditos_usados ?? 0)
      const subject = esExperiencia
        ? `Se canceló ${clase.nombre ?? 'la experiencia'}`
        : `Se canceló tu clase en ${estudioNombre}`
      const html = renderHtml({
        nombre,
        claseNombre: String(clase.nombre ?? (esExperiencia ? 'la experiencia' : 'tu clase')),
        estudioNombre, fechaStr, horaStr, creditos, esExperiencia,
      })

      if (dryRun) {
        resultados.push({ reserva: r.id, para: email, asunto: subject, creditos })
        enviados++
        continue
      }

      const res = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${RESEND_API_KEY}`,
          'Content-Type': 'application/json',
        },
        // `to` con UNA sola dirección: nunca el lote junto.
        body: JSON.stringify({
          from: FROM_EMAIL,
          reply_to: 'aura.hola.app@gmail.com',
          to: email,
          subject,
          html,
        }),
      })
      if (res.ok) {
        enviados++
        resultados.push({ reserva: r.id, para: email, ok: true })
      } else {
        // Un fallo no corta el lote: el resto tiene que enterarse igual.
        fallidos++
        const detail = await res.text().catch(() => '')
        console.error('cancelacion-email resend error:', r.id, detail)
        resultados.push({ reserva: r.id, para: email, ok: false, detail })
      }
    }

    return json({
      ok: true,
      dry_run: dryRun,
      clase: clase.nombre,
      reservas: (reservas ?? []).length,
      enviados,
      fallidos,
      resultados,
    })
  } catch (e) {
    console.error('cancelacion-email exception:', e)
    return json({ error: 'Error interno', detail: e instanceof Error ? e.message : String(e) }, 500)
  }
})

function formatearFecha(raw: string): { fechaStr: string; horaStr: string } {
  const d = new Date(raw.replace(' ', 'T'))
  if (isNaN(d.getTime())) return { fechaStr: '', horaStr: '' }
  // Las fechas en la base ya están en hora Argentina, sin marcador de zona:
  // se formatea en UTC para no correrlas 3 horas. Misma decisión que
  // aviso-alumnos-email (bug del 25/8).
  const dias = ['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado']
  const meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre']
  const fechaStr = `${dias[d.getUTCDay()]} ${d.getUTCDate()} de ${meses[d.getUTCMonth()]}`
  const hh = String(d.getUTCHours()).padStart(2, '0')
  const mm = String(d.getUTCMinutes()).padStart(2, '0')
  return { fechaStr, horaStr: `${hh}:${mm}` }
}

function renderHtml(a: {
  nombre: string
  claseNombre: string
  estudioNombre: string
  fechaStr: string
  horaStr: string
  creditos: number
  esExperiencia: boolean
}): string {
  const hola = a.nombre ? `¡Hola ${escape(a.nombre)}!` : '¡Hola!'
  const que = a.esExperiencia ? 'la experiencia' : 'la clase'
  const cuando = a.fechaStr ? ` del ${a.fechaStr} a las ${a.horaStr} hs` : ''
  const devolucion = a.creditos > 0
    ? `Te devolvimos tus <strong>${a.creditos} créditos</strong>, ya están disponibles en tu cuenta.`
    : 'No se te descontaron créditos.'
  return `<!doctype html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Aura</title></head>
<body style="font-family:-apple-system,Arial,sans-serif; background:#F7F5F2; margin:0; padding:24px;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px; margin:0 auto; background:#fff; border-radius:16px; overflow:hidden;">
    <tr><td style="background:#1A1A1A; padding:32px 24px; text-align:center;">
      <div style="color:#E8763A; font-size:28px; font-weight:800; letter-spacing:6px;">AURA.</div>
      <div style="color:#888; font-size:11px; margin-top:8px; letter-spacing:2px;">CLASE CANCELADA</div>
    </td></tr>
    <tr><td style="padding:28px 24px;">
      <p style="margin:0 0 16px; color:#1A1A1A; font-size:16px; line-height:1.5;">${hola}</p>
      <p style="margin:0 0 16px; color:#1A1A1A; font-size:16px; line-height:1.5;">
        <strong>${escape(a.estudioNombre)}</strong> canceló ${que} <strong>${escape(a.claseNombre)}</strong>${cuando}.
      </p>
      <div style="background:#FFF1E8; border-left:4px solid #E8763A; padding:16px; border-radius:8px; margin:16px 0; color:#1A1A1A; font-size:15px; line-height:1.8;">
        ${devolucion}
      </div>
      <p style="margin:16px 0 0; color:#555; font-size:14px; text-align:center;">
        <a href="https://somosaurapass.com/#/explorar" style="display:inline-block;background:#E8763A;color:#fff;text-decoration:none;padding:12px 22px;border-radius:10px;font-weight:700;">Buscar otra clase</a>
      </p>
    </td></tr>
    <tr><td style="background:#F7F5F2; padding:16px 24px; text-align:center; color:#888; font-size:11px;">
      Recibís este mail porque tenías una reserva en esta clase.
    </td></tr>
  </table>
</body></html>`
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
