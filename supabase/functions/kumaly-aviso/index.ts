// Aviso de envíos a Kumaly trabados — 19/11/2026.
//
// La llama el cron `kumaly-aviso-trabados` todos los días a las 10:00 de
// Argentina, y SÓLO si `kumaly_hay_trabados()` da true: si no hay nada
// trabado, no se llama y no sale ningún mail. Igual, si se la llama y no hay
// nada, no manda (por si alguien la invoca a mano).
//
// Manda un mail a la casilla del resumen diario (AURA_RESUMEN_EMAIL, por
// defecto aura.hola.app@gmail.com) con lo que `kumaly_trabados()` devuelve:
// envíos pendientes que fallaron 3 veces o más, y reservas que se cayeron en
// las últimas 24 h porque Kumaly nunca las confirmó.
//
// Auth: bearer == service role key (lo manda el cron desde el Vault).
// {"dry_run": true} arma el mail y lo devuelve sin mandarlo.

import { createClient } from 'npm:@supabase/supabase-js@2.57.4'
import { htmlATexto, REPLY_TO } from '../_shared/email.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? ''
const FROM_EMAIL = Deno.env.get('AURA_FROM_EMAIL') ?? 'Aura <hola@somosaurapass.com>'
const PARA = Deno.env.get('AURA_RESUMEN_EMAIL') ?? 'aura.hola.app@gmail.com'

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)

type Fila = {
  id: number
  evento: string
  estudio: string | null
  clase: string | null
  inicio: string | null
  alumna: string | null
  intentos: number
  ultimo_status: number | null
  ultimo_error: string
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

function esc(s: unknown): string {
  return String(s ?? '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
}

/// "2026-11-20T18:00:00-03:00" → "20/11 18:00".
function cuando(iso: string | null): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(iso ?? '')
  return m ? `${m[3]}/${m[2]} ${m[4]}:${m[5]}` : esc(iso)
}

function explicar(f: Fila): string {
  const st = f.ultimo_status
  if (st === null || st === 0) return 'Kumaly no contesta'
  if (st === 401) return 'Kumaly rechaza la clave (401)'
  if (st === 404 && f.ultimo_error.includes('clase_no_encontrada')) return 'Kumaly no tiene esa clase (404)'
  if (st === 404 && f.ultimo_error.includes('estudio_no_encontrado')) return 'Kumaly no tiene ese estudio (404)'
  if (st === 400) return 'Kumaly dice que faltan datos (400)'
  if (st >= 500) return `Error de Kumaly (${st})`
  return `Respuesta ${st}`
}

function tabla(filas: Fila[]): string {
  const td = 'padding:6px 8px;border-bottom:1px solid #333;color:#F5F0E8;font-size:13px;font-family:Arial,sans-serif;vertical-align:top'
  const th = td.replace('#F5F0E8', '#B8B0A9')
  return `<table role="presentation" cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse;margin:0 0 20px">
    <tr><th align="left" style="${th}">Clase</th><th align="left" style="${th}">Alumna</th><th align="left" style="${th}">Qué pasa</th></tr>
    ${filas.map((f) => `<tr>
      <td style="${td}">${esc(f.clase)} · ${cuando(f.inicio)}<br><span style="color:#B8B0A9">${esc(f.estudio)}${f.evento === 'cancelacion' ? ' · cancelación' : ''}</span></td>
      <td style="${td}">${esc(f.alumna) || '—'}</td>
      <td style="${td}">${esc(explicar(f))}<br><span style="color:#B8B0A9">${f.intentos} intento${f.intentos === 1 ? '' : 's'} · envío #${f.id}</span></td>
    </tr>`).join('')}
  </table>`
}

function renderHtml(pend: Fila[], venc: Fila[]): string {
  const P = 'margin:0 0 12px;color:#B8B0A9;font-size:15px;line-height:1.6;font-family:Arial,sans-serif'
  const H = 'margin:20px 0 8px;color:#F5F0E8;font-size:16px;font-family:Arial,sans-serif'
  return `<!doctype html>
<html lang="es"><body style="margin:0;padding:0;background:#0D0D0D">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#0D0D0D;padding:32px 16px">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#1A1A1A;border-radius:20px;padding:28px">
        <tr><td>
          <p style="margin:0 0 20px;color:#E8763A;font-size:15px;font-weight:800;letter-spacing:4px">AURA.</p>
          <p style="${P}">Hay envíos a Kumaly que no están entrando.</p>
          ${pend.length ? `<p style="${H}">Trabados ahora (${pend.length})</p>
          <p style="${P}">Se siguen reintentando cada 10 minutos. Si no entran antes de que empiece la clase, la reserva se cancela y se le devuelven los créditos a la alumna.</p>
          ${tabla(pend)}` : ''}
          ${venc.length ? `<p style="${H}">Se cayeron en las últimas 24 h (${venc.length})</p>
          <p style="${P}">Kumaly nunca las confirmó: se cancelaron y a la alumna se le devolvieron los créditos y se le avisó. El estudio no las tuvo.</p>
          ${tabla(venc)}` : ''}
          <p style="${P}">El detalle está en la tabla <code>kumaly_envios</code>. Este mail sólo sale los días en que hay algo trabado.</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`
}

Deno.serve(async (req) => {
  const bearer = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '').trim()
  if (bearer !== SERVICE_ROLE_KEY) return json({ error: 'no_autorizado' }, 401)

  const body = await req.json().catch(() => ({}))
  const dryRun = (body as { dry_run?: boolean })?.dry_run === true

  const { data, error } = await admin.rpc('kumaly_trabados')
  if (error) {
    console.error('kumaly_trabados falló:', error.message)
    return json({ error: 'error_interno' }, 500)
  }
  const pend = ((data as { pendientes?: Fila[] })?.pendientes ?? [])
  const venc = ((data as { vencidos_24h?: Fila[] })?.vencidos_24h ?? [])
  if (pend.length + venc.length === 0) return json({ ok: true, enviado: false, motivo: 'nada_trabado' })

  const asunto = `Kumaly: ${pend.length + venc.length} envío${pend.length + venc.length === 1 ? '' : 's'} con problemas`
  const html = renderHtml(pend, venc)
  if (dryRun) return json({ ok: true, enviado: false, dry_run: true, para: PARA, asunto, html })
  if (!RESEND_API_KEY) return json({ error: 'RESEND_API_KEY no configurada' }, 500)

  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from: FROM_EMAIL, reply_to: REPLY_TO, to: PARA, subject: asunto, html, text: htmlATexto(html) }),
  })
  if (!res.ok) {
    const detalle = await res.text().catch(() => '')
    console.error('kumaly-aviso resend error:', res.status, detalle)
    return json({ error: 'resend', status: res.status }, 502)
  }
  return json({ ok: true, enviado: true, para: PARA, pendientes: pend.length, vencidos: venc.length })
})
