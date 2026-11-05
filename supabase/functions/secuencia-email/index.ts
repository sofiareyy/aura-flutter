// secuencia-email — los 3 mails de bienvenida para quien se registra y no compra.
//
// La dispara el cron `secuencia-bienvenida` (cada 10 min, por secuencia_tick)
// solo cuando hay algo para mandar. No decide a quién: le pregunta a la base
// (secuencia_a_enviar), que es la que aplica todas las reglas en el momento
// (compró, baja, rebote, interna, estudio, interruptor apagado). Antes de cada
// mail lo "toma" (secuencia_tomar) para que dos disparos a la vez no manden dos.
//
// Auth: header `x-notif-secret` == NOTIF_TRIGGER_SECRET (fail-closed).
// MODO TEST: {"test_email": "...", "test_pasos": [1,2,3], "test_usuario_id": "<uuid>",
// "test_nombre": "Sofi"} manda solo a esa casilla y no registra nada.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { htmlATexto, REPLY_TO } from '../_shared/email.ts'
import { headersDeBaja, linkDeBaja } from '../_shared/baja.ts'
import { armarMail, type Paso } from './mail.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? ''
const FROM_EMAIL = Deno.env.get('AURA_FROM_EMAIL') ?? 'Aura <hola@somosaurapass.com>'
const TRIGGER_SECRET = Deno.env.get('NOTIF_TRIGGER_SECRET') ?? ''
const BAJA_SECRET = Deno.env.get('MAIL_BAJA_SECRET') ?? ''

const PAUSA_MS = 700

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  try {
    if (!RESEND_API_KEY) return json({ error: 'RESEND_API_KEY no configurada' }, 500)
    if (!BAJA_SECRET) return json({ error: 'MAIL_BAJA_SECRET no configurado' }, 500)
    if (!TRIGGER_SECRET || req.headers.get('x-notif-secret') !== TRIGGER_SECRET) {
      return json({ error: 'No autorizado' }, 401)
    }
    const body = await req.json().catch(() => null)

    // ── Modo test ──────────────────────────────────────────────────────────
    const testEmail = typeof body?.test_email === 'string' ? body.test_email.trim().toLowerCase() : ''
    if (testEmail) {
      const pasos = (Array.isArray(body?.test_pasos) ? body.test_pasos : [1, 2, 3])
        .map(Number).filter((n: number) => n === 1 || n === 2 || n === 3) as Paso[]
      const uid = typeof body?.test_usuario_id === 'string' ? body.test_usuario_id : '00000000-0000-0000-0000-000000000000'
      const resultados = []
      for (const paso of pasos) {
        // Asunto propio en cada prueba: si no, Gmail junta las pruebas en una
        // conversación y esconde detrás de "···" lo que se repite (el 20%, el botón).
        const hora = new Date().toLocaleTimeString('es-AR', { timeZone: 'America/Argentina/Buenos_Aires', hour: '2-digit', minute: '2-digit' })
        resultados.push({ paso, ...(await enviar(paso, testEmail, uid, String(body?.test_nombre ?? 'Sofi'), `[Prueba ${hora}] `)) })
        await new Promise((r) => setTimeout(r, PAUSA_MS))
      }
      return json({ ok: resultados.every((r) => r.ok), test: true, resultados })
    }

    // ── Envío real ─────────────────────────────────────────────────────────
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)
    const { data: pendientes, error } = await admin.rpc('secuencia_a_enviar', { p_limite: 50 })
    if (error) return json({ error: 'lectura_fallo', detalle: error.message }, 500)

    const resumen = { enviados: 0, errores: 0, salteados: 0 }
    for (const f of (pendientes ?? []) as { usuario_id: string; paso: Paso; email: string; nombre: string | null }[]) {
      const { data: mia } = await admin.rpc('secuencia_tomar', {
        p_usuario_id: f.usuario_id, p_paso: f.paso, p_email: f.email,
      })
      if (mia !== true) { resumen.salteados++; continue }

      const r = await enviar(f.paso, f.email, f.usuario_id, f.nombre ?? '')
      await admin.from('secuencia_mails').update(r.ok
        ? { estado: 'enviado', resend_id: r.resend_id ?? null, enviado_at: new Date().toISOString() }
        : { estado: `error: ${String(r.detalle ?? '').slice(0, 200)}` })
        .eq('usuario_id', f.usuario_id).eq('paso', f.paso)
      if (r.ok) resumen.enviados++
      else resumen.errores++
      await new Promise((res) => setTimeout(res, PAUSA_MS))
    }
    return json({ ok: true, ...resumen })
  } catch (e) {
    return json({ error: String(e) }, 500)
  }
})

async function enviar(paso: Paso, email: string, usuarioId: string, nombre: string, prefijo = ''):
  Promise<{ ok: boolean; resend_id?: string; detalle?: string; subject?: string }> {
  const baja = await linkDeBaja(usuarioId, BAJA_SECRET)
  const { subject, html } = armarMail(paso, nombre, baja)
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      from: FROM_EMAIL,
      reply_to: REPLY_TO,
      to: email,
      subject: prefijo + subject,
      html,
      text: htmlATexto(html),
      headers: await headersDeBaja(usuarioId, BAJA_SECRET),
    }),
  })
  if (!res.ok) return { ok: false, subject, detalle: `${res.status} ${(await res.text()).slice(0, 200)}` }
  const out = await res.json().catch(() => ({})) as { id?: string }
  return { ok: true, subject, resend_id: out.id }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
