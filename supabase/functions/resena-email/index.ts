// Mails de reseñas, dos modos:
//   kind 'nueva'  -> aviso a los admins del estudio: alguien dejó una reseña.
//   kind 'pedido' -> a la alumna que ASISTIÓ (check-in), 15 min después de la
//                    clase: "¿qué te pareció? dejá tu reseña".
// La dispara la base (trigger de study_reviews / cron pedir_resenas_post_clase)
// vía pg_net, con el mismo secreto compartido que nueva-reserva-estudio-email.
// Auth: header `x-notif-secret` == NOTIF_TRIGGER_SECRET (fail-closed).
//
// MODO TEST: si el body trae `test_email`, manda SOLO a esa casilla e ignora
// los destinatarios reales. Mismo patrón que nueva-reserva-estudio-email:
// sirve para revisar el render sin escribirle a un estudio de verdad.

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
    const kind = body?.kind
    const testEmail = typeof body?.test_email === 'string'
      ? body.test_email.trim().toLowerCase()
      : ''
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)

    if (kind === 'nueva') {
      // ── Aviso al estudio: reseña nueva ────────────────────────────────────
      const reviewId = Number(body?.review_id)
      if (!reviewId) return json({ error: 'Falta review_id' }, 400)

      const { data: r } = await admin
        .from('study_reviews')
        .select('estudio_id, usuario_id, rating, comentario')
        .eq('id', reviewId)
        .maybeSingle()
      if (!r) return json({ error: 'Reseña no encontrada' }, 404)

      const { data: estudio } = await admin
        .from('estudios').select('nombre').eq('id', r.estudio_id).maybeSingle()
      const { data: autora } = await admin
        .from('usuarios').select('nombre, rol').eq('id', r.usuario_id).maybeSingle()
      // Cuenta borrada (lápida): sin nombre real.
      const nombre = (autora?.rol === 'eliminado')
        ? 'Anónimo' : ((autora?.nombre as string | null)?.trim() || 'Una alumna')

      // Mismos destinatarios que el aviso de reserva: los admins (sin profes),
      // salteando a la autora si fuera admin.
      const { data: admins } = await admin
        .from('estudio_admins')
        .select('usuario_id, rol')
        .eq('estudio_id', r.estudio_id)
        .neq('rol', 'profe')
      const emails: string[] = []
      for (const a of admins ?? []) {
        if (String(a.usuario_id) === String(r.usuario_id)) continue
        const { data: u } = await admin.auth.admin.getUserById(String(a.usuario_id))
        const email = u?.user?.email?.trim().toLowerCase()
        if (email && email.includes('@') && !email.endsWith('@cuenta-eliminada.aura')) {
          emails.push(email)
        }
      }
      const destinatarios = testEmail ? [testEmail] : [...new Set(emails)]
      if (destinatarios.length === 0) return json({ ok: true, enviados: 0 })

      const estrellas = '⭐'.repeat(Math.max(1, Math.min(5, Number(r.rating) || 0)))
      const subject = `Nueva reseña en ${estudio?.nombre ?? 'tu estudio'} — ${estrellas}`
      const html = plantilla(
        'NUEVA RESEÑA',
        `<strong>${escape(nombre)}</strong> dejó una reseña en <strong>${escape(estudio?.nombre ?? 'tu estudio')}</strong> 🧡`,
        `${estrellas}<br><em>“${escape(String(r.comentario ?? '').slice(0, 400))}”</em>`,
        'Podés ver todas tus reseñas en la app.',
        'Recibís este mail porque administrás este estudio en Aura.',
      )
      return await enviar(destinatarios, subject, html)
    }

    if (kind === 'pedido') {
      // ── A la alumna: dejá tu reseña ───────────────────────────────────────
      const usuarioId = String(body?.usuario_id ?? '')
      const estudioId = Number(body?.estudio_id)
      const claseNombre = String(body?.clase_nombre ?? 'tu clase')
      if (!usuarioId || !estudioId) return json({ error: 'Faltan datos' }, 400)

      let email = testEmail
      if (!email) {
        const { data: u } = await admin.auth.admin.getUserById(usuarioId)
        email = u?.user?.email?.trim().toLowerCase() ?? ''
      }
      if (!email || !email.includes('@') || email.endsWith('@cuenta-eliminada.aura')) {
        return json({ ok: true, enviados: 0, motivo: 'sin_email' })
      }
      const { data: estudio } = await admin
        .from('estudios').select('nombre').eq('id', estudioId).maybeSingle()
      const estudioNombre = estudio?.nombre ?? 'el estudio'

      // "Citra barre" (la clase) EN "Citra Barre" (el estudio) repetía el
      // nombre. La clase se nombra sólo si aporta algo distinto; si es la
      // misma palabra, o una contiene a la otra, alcanza con el estudio.
      const norm = (x: string) => x.toLowerCase()
        .normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim()
      const nc = norm(claseNombre), ne = norm(estudioNombre)
      const claseAporta = nc.length > 0 && ne.length > 0
        && nc !== ne && !ne.includes(nc) && !nc.includes(ne)

      const subject = `¿Qué te pareció tu clase en ${estudioNombre}?`
      const html = plantilla(
        'TU OPINIÓN VALE',
        claseAporta
          ? `¡Qué bueno tenerte en <strong>${escape(claseNombre)}</strong>, en <strong>${escape(estudioNombre)}</strong>! 🧡`
          : `¡Qué bueno tenerte en <strong>${escape(estudioNombre)}</strong>! 🧡`,
        `Esperamos que la hayas pasado bien 🌿<br>Contanos cómo estuvo: tu reseña ayuda a que otras personas descubran este lugar.`,
        `<a href="https://somosaurapass.com/#/estudio/${estudioId}" style="display:inline-block;background:#E8763A;color:#fff;text-decoration:none;padding:12px 22px;border-radius:10px;font-weight:700;">Dejar mi reseña</a>`,
        'Recibís este mail porque asististe a una clase reservada por Aura.',
      )
      return await enviar([email], subject, html)
    }

    return json({ error: 'kind inválido' }, 400)
  } catch (e) {
    console.error('resena-email exception:', e)
    return json({ error: 'Error interno', detail: e instanceof Error ? e.message : String(e) }, 500)
  }
})

async function enviar(to: string[], subject: string, html: string) {
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from: FROM_EMAIL, reply_to: 'aura.hola.app@gmail.com', to, subject, html }),
  })
  if (!res.ok) {
    const detail = await res.text().catch(() => '')
    return json({ ok: false, error: 'resend_error', detail }, 502)
  }
  const out = await res.json().catch(() => ({}))
  return json({ ok: true, enviados: to.length, resend_id: (out as { id?: string })?.id })
}

function plantilla(tag: string, titulo: string, cuerpo: string, extra: string, pie: string): string {
  return `<!doctype html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Aura</title></head>
<body style="font-family:-apple-system,Arial,sans-serif; background:#F7F5F2; margin:0; padding:24px;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px; margin:0 auto; background:#fff; border-radius:16px; overflow:hidden;">
    <tr><td style="background:#1A1A1A; padding:32px 24px; text-align:center;">
      <div style="color:#E8763A; font-size:28px; font-weight:800; letter-spacing:6px;">AURA.</div>
      <div style="color:#888; font-size:11px; margin-top:8px; letter-spacing:2px;">${tag}</div>
    </td></tr>
    <tr><td style="padding:28px 24px;">
      <p style="margin:0 0 16px; color:#1A1A1A; font-size:16px; line-height:1.5;">${titulo}</p>
      <div style="background:#FFF1E8; border-left:4px solid #E8763A; padding:16px; border-radius:8px; margin:16px 0; color:#1A1A1A; font-size:15px; line-height:1.8;">${cuerpo}</div>
      <p style="margin:16px 0 0; color:#555; font-size:14px; text-align:center;">${extra}</p>
    </td></tr>
    <tr><td style="background:#F7F5F2; padding:16px 24px; text-align:center; color:#888; font-size:11px;">${pie}</td></tr>
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
