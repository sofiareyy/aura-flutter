// regalo-email — los mails del regalo de créditos por sorteo.
//
// La dispara la base (`_regalo_disparar_mails`, desde regalo_otorgar y desde
// el cron diario regalo_recordatorios) con {campana}. No recibe a quién
// escribir: busca en `regalo_campana` los mails PENDIENTES y los manda de a
// uno, anotando el resultado en la misma fila. Así es idempotente: llamarla
// dos veces no manda dos veces, y si un mail falla queda pendiente para el
// reintento del día siguiente (hasta 3 intentos).
//
// Dos mails:
// - 'regalo': cuando se acreditan los créditos.
// - 'recordatorio': a los 10 días, si no usó nada (lo decide la base).
//
// Respeta las bajas (`mail_bajas`): a quien se dio de baja no se le manda,
// y queda anotado como 'omitido_baja'. Cada mail lleva el link de baja al pie
// y el encabezado List-Unsubscribe (botón de Gmail).
//
// Auth: header `x-notif-secret` == NOTIF_TRIGGER_SECRET (fail-closed).
// MODO TEST: {"test_email": "...", "test_kind": "regalo"|"recordatorio",
// "test_usuario_id": "<uuid para armar el link de baja>"} manda SOLO a esa
// casilla con datos de ejemplo y no toca ninguna fila.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { htmlATexto, REPLY_TO } from '../_shared/email.ts'
import { headersDeBaja, linkDeBaja, pieDeBaja } from '../_shared/baja.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? ''
const FROM_EMAIL = Deno.env.get('AURA_FROM_EMAIL') ?? 'Aura <hola@somosaurapass.com>'
const TRIGGER_SECRET = Deno.env.get('NOTIF_TRIGGER_SECRET') ?? ''
const BAJA_SECRET = Deno.env.get('MAIL_BAJA_SECRET') ?? ''

const WEB = 'https://somosaurapass.com'
const MAX_INTENTOS = 3
// Resend acepta pocos pedidos por segundo; de a uno con pausa no se pasa.
const PAUSA_MS = 700

type Kind = 'regalo' | 'recordatorio'

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  try {
    if (!RESEND_API_KEY) return json({ error: 'RESEND_API_KEY no configurada' }, 500)
    if (!BAJA_SECRET) return json({ error: 'MAIL_BAJA_SECRET no configurado' }, 500)
    if (!TRIGGER_SECRET || req.headers.get('x-notif-secret') !== TRIGGER_SECRET) {
      return json({ error: 'No autorizado' }, 401)
    }

    const body = await req.json().catch(() => null)

    // ── Consultar en Resend qué pasó con los mails de una campaña ──────────
    // {"consultar": "<campana>"}: pregunta por cada mail enviado, devuelve el
    // último evento (delivered, bounced, complained...) y si rebotó o lo
    // marcaron como spam, lo anota en mail_bajas para no volver a escribirle
    // nunca (pedido de Sofía, 3/11/2026).
    if (typeof body?.consultar === 'string' && body.consultar) {
      const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)
      const { data: filas, error } = await admin.from('regalo_campana')
        .select('usuario_id, email, mail_regalo_id, mail_recordatorio_id')
        .eq('campana', body.consultar)
      if (error) return json({ error: 'lectura_fallo', detalle: error.message }, 500)
      const resultados: { email: string; mail: string; evento: string }[] = []
      for (const f of filas ?? []) {
        for (const [mail, id] of [['regalo', f.mail_regalo_id], ['recordatorio', f.mail_recordatorio_id]] as const) {
          if (!id) continue
          const r = await fetch(`https://api.resend.com/emails/${id}`, {
            headers: { 'Authorization': `Bearer ${RESEND_API_KEY}` },
          })
          const d = await r.json().catch(() => ({})) as { last_event?: string }
          const evento = r.ok ? String(d.last_event ?? 'desconocido') : `error_${r.status}`
          resultados.push({ email: f.email, mail, evento })
          const origen = evento === 'complained' ? 'queja'
            : evento !== 'bounced' ? null
            : String(f.email).toLowerCase().endsWith('@privaterelay.appleid.com') ? 'rebote_apple' : 'rebote'
          if (origen) {
            await admin.from('mail_bajas').upsert(
              { email: String(f.email).toLowerCase(), usuario_id: f.usuario_id, origen },
              { onConflict: 'email', ignoreDuplicates: true },
            )
            const col = mail === 'regalo' ? 'mail_regalo_estado' : 'mail_recordatorio_estado'
            await admin.from('regalo_campana').update({ [col]: origen === 'queja' ? 'marcado_como_spam' : 'rebotó' })
              .eq('campana', body.consultar).eq('usuario_id', f.usuario_id)
          }
          await new Promise((res) => setTimeout(res, PAUSA_MS))
        }
      }
      const porEvento: Record<string, number> = {}
      for (const r of resultados) porEvento[r.evento] = (porEvento[r.evento] ?? 0) + 1
      return json({ ok: true, campana: body.consultar, por_evento: porEvento, resultados })
    }

    // ── Modo test ──────────────────────────────────────────────────────────
    const testEmail = typeof body?.test_email === 'string' ? body.test_email.trim().toLowerCase() : ''
    if (testEmail) {
      const kind: Kind = body?.test_kind === 'recordatorio' ? 'recordatorio' : 'regalo'
      const uid = typeof body?.test_usuario_id === 'string' ? body.test_usuario_id : '00000000-0000-0000-0000-000000000000'
      const vence = new Date(Date.now() + (kind === 'regalo' ? 14 : 4) * 86400000).toISOString().slice(0, 10)
      const r = await enviar({
        kind, campana: 'prueba', email: testEmail, usuarioId: uid,
        nombre: String(body?.test_nombre ?? 'Sofi'), monto: 20, vence,
      })
      return json({ ok: r.ok, test: true, kind, ...r })
    }

    const campana = typeof body?.campana === 'string' ? body.campana : ''
    if (!campana) return json({ error: 'Falta campana' }, 400)

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)
    const resumen = { regalo: { enviados: 0, omitidos: 0, errores: 0 }, recordatorio: { enviados: 0, omitidos: 0, errores: 0 } }

    for (const kind of ['regalo', 'recordatorio'] as Kind[]) {
      const colAt = kind === 'regalo' ? 'mail_regalo_at' : 'mail_recordatorio_at'
      const colEstado = kind === 'regalo' ? 'mail_regalo_estado' : 'mail_recordatorio_estado'
      const colId = kind === 'regalo' ? 'mail_regalo_id' : 'mail_recordatorio_id'
      const colIntentos = kind === 'regalo' ? 'intentos_regalo' : 'intentos_recordatorio'
      const colListo = kind === 'regalo' ? 'otorgado_at' : 'recordatorio_at'

      const { data: pendientes, error } = await admin
        .from('regalo_campana')
        .select(`usuario_id, email, monto, vence, lote_id, ${colIntentos}`)
        .eq('campana', campana)
        .not(colListo, 'is', null)
        .is(colAt, null)
        .lt(colIntentos, MAX_INTENTOS)
      if (error) return json({ error: 'lectura_fallo', detalle: error.message }, 500)

      for (const p of pendientes ?? []) {
        // Reservar la fila: si otra llamada ya la tomó, el update no matchea.
        const intentos = Number((p as Record<string, unknown>)[colIntentos] ?? 0)
        const { data: tomada } = await admin
          .from('regalo_campana')
          .update({ [colIntentos]: intentos + 1 })
          .eq('campana', campana).eq('usuario_id', p.usuario_id)
          .eq(colIntentos, intentos).is(colAt, null)
          .select('usuario_id')
        if (!tomada || tomada.length === 0) continue

        const { data: u } = await admin
          .from('usuarios').select('nombre, email').eq('id', p.usuario_id).maybeSingle()
        if (!u) {
          await admin.from('regalo_campana')
            .update({ [colAt]: new Date().toISOString(), [colEstado]: 'omitido_cuenta_borrada' })
            .eq('campana', campana).eq('usuario_id', p.usuario_id)
          resumen[kind].omitidos++
          continue
        }
        const email = String(u.email ?? p.email).trim().toLowerCase()

        const { data: baja } = await admin.from('mail_bajas').select('email').eq('email', email).maybeSingle()
        if (baja) {
          await admin.from('regalo_campana')
            .update({ [colAt]: new Date().toISOString(), [colEstado]: 'omitido_baja' })
            .eq('campana', campana).eq('usuario_id', p.usuario_id)
          resumen[kind].omitidos++
          continue
        }

        // Para el recordatorio, lo que queda del lote (la base ya chequeó que esté entero).
        let monto = Number(p.monto ?? 20)
        let vence = String(p.vence ?? '')
        if (p.lote_id) {
          const { data: lote } = await admin.from('creditos_movimientos')
            .select('amount_remaining, expires_at').eq('id', p.lote_id).maybeSingle()
          if (lote && kind === 'recordatorio') monto = Number(lote.amount_remaining ?? monto)
          if (lote?.expires_at) vence = String(lote.expires_at)
        }

        const r = await enviar({
          kind, campana, email, usuarioId: p.usuario_id,
          nombre: String(u.nombre ?? '').trim().split(' ')[0] || '', monto, vence,
        })
        if (r.ok) {
          await admin.from('regalo_campana')
            .update({ [colAt]: new Date().toISOString(), [colEstado]: 'enviado', [colId]: r.resend_id ?? null })
            .eq('campana', campana).eq('usuario_id', p.usuario_id)
          resumen[kind].enviados++
        } else {
          await admin.from('regalo_campana')
            .update({ [colEstado]: `error: ${String(r.detalle ?? '').slice(0, 200)}` })
            .eq('campana', campana).eq('usuario_id', p.usuario_id)
          resumen[kind].errores++
        }
        await new Promise((res) => setTimeout(res, PAUSA_MS))
      }
    }

    return json({ ok: true, campana, ...resumen })
  } catch (e) {
    return json({ error: String(e) }, 500)
  }
})

async function enviar(p: {
  kind: Kind; campana: string; email: string; usuarioId: string
  nombre: string; monto: number; vence: string
}): Promise<{ ok: boolean; resend_id?: string; detalle?: string }> {
  const link = `${WEB}/?utm_source=email&utm_medium=email&utm_campaign=${encodeURIComponent('regalo_' + p.campana)}&utm_content=${p.kind}#/explorar`
  const baja = await linkDeBaja(p.usuarioId, BAJA_SECRET)
  const fecha = fechaLarga(p.vence)
  const saludo = p.nombre ? `Hola ${p.nombre},` : 'Hola,'

  const asunto = p.kind === 'recordatorio'
    ? `Tus ${p.monto} créditos de regalo vencen el ${fecha}`
    : `Te regalamos ${p.monto} créditos para probar Aura 🧡`
  const html = renderHtml({ ...p, saludo, fecha, link, baja, diasRestantes: diasHasta(p.vence) })

  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      from: FROM_EMAIL,
      reply_to: REPLY_TO,
      to: p.email,
      subject: asunto,
      html,
      text: htmlATexto(html),
      headers: await headersDeBaja(p.usuarioId, BAJA_SECRET),
    }),
  })
  if (!res.ok) return { ok: false, detalle: `${res.status} ${(await res.text()).slice(0, 200)}` }
  const out = await res.json().catch(() => ({}))
  return { ok: true, resend_id: (out as { id?: string })?.id }
}

function hoyArgentina(): string {
  return new Date().toLocaleDateString('en-CA', { timeZone: 'America/Argentina/Buenos_Aires' })
}

function diasHasta(iso: string): number {
  const a = Date.parse(hoyArgentina() + 'T12:00:00Z')
  const b = Date.parse(iso.slice(0, 10) + 'T12:00:00Z')
  return Math.max(0, Math.round((b - a) / 86400000))
}

function fechaLarga(iso: string): string {
  try {
    const d = new Date(iso.slice(0, 10) + 'T12:00:00Z')
    return d.toLocaleDateString('es-AR', { day: 'numeric', month: 'long', timeZone: 'America/Argentina/Buenos_Aires' })
  } catch (_) {
    return iso
  }
}

const P = 'margin:0 0 16px;color:#B8B0A9;font-size:15px;line-height:1.6;font-family:Arial,sans-serif'

function renderHtml(p: {
  kind: Kind; saludo: string; monto: number; fecha: string; link: string; baja: string; diasRestantes: number
}): string {
  const cuerpo = p.kind === 'recordatorio'
    ? `<p style="${P}">${p.saludo}</p>
       <p style="${P}">Te quedan ${p.diasRestantes === 1 ? '1 día' : `${p.diasRestantes} días`} para usar los
         <strong style="color:#F5F0E8">${p.monto} créditos</strong> que te regalamos: vencen el
         <strong style="color:#F5F0E8">${p.fecha}</strong>.</p>
       <p style="${P}">Alcanzan para una clase, la que vos elijas: pilates, yoga, spinning, barre y mucho más.
         Reservás en un minuto desde Aura.</p>`
    : `<p style="${P}">${p.saludo}</p>
       <p style="${P}">Te regalamos <strong style="color:#F5F0E8">${p.monto} créditos</strong> para que pruebes
         una clase en Aura. Ya están en tu cuenta.</p>
       <p style="${P}">Alcanzan para una clase, la que vos elijas: pilates, yoga, spinning, barre y mucho más,
         en el estudio que más te guste.</p>
       <p style="${P}">Los podés usar hasta el <strong style="color:#F5F0E8">${p.fecha}</strong>.</p>`

  return `<!doctype html>
<html lang="es"><body style="margin:0;padding:0;background:#0D0D0D">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#0D0D0D;padding:32px 16px">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;background:#1A1A1A;border-radius:20px;padding:32px">
        <tr><td>
          <p style="margin:0 0 24px;color:#E8763A;font-size:15px;font-weight:800;letter-spacing:4px">AURA.</p>
          ${cuerpo}
          <p style="margin:8px 0 24px">
            <a href="${p.link}"
               style="display:inline-block;background:#E8763A;color:#fff;text-decoration:none;
                      padding:14px 28px;border-radius:12px;font-weight:700;font-size:15px;font-family:Arial,sans-serif">
              Elegir mi clase
            </a>
          </p>
          <p style="${P}">Y si necesitás ayuda, respondeme este mail.</p>
          <p style="margin:0;color:#F5F0E8;font-size:15px;line-height:1.6;font-family:Arial,sans-serif">Sofi, de Aura 🧡</p>
          ${pieDeBaja(p.baja)}
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
