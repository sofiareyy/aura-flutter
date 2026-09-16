// El resumen diario del negocio, a la casilla de Aura.
//
// Pocos números, los que hacen actuar. Sale TODOS los días aunque esté todo en
// cero: un mail que no llega es la señal de que algo se rompió, y por eso van
// numerados — si ves el #36 y nunca viste el #35, falló algo.
//
// Los números se calculan en la base (`resumen_diario_preparar`), no acá: así
// el mail y cualquier otra vista no se pueden separar. Esa función también
// registra el envío, así que si el cron corre dos veces la segunda no manda
// nada.
//
// Las cuentas internas (testers de Android, la cuenta de pruebas) NO cuentan:
// sin ese filtro septiembre marcaba 29 altas y las reales eran 13.
//
// Auth: header `x-notif-secret` == NOTIF_TRIGGER_SECRET (fail-closed).
// `dry_run: true` arma el mail y lo devuelve sin mandarlo.
// `test_email` lo manda a otra casilla.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? ''
const FROM_EMAIL = Deno.env.get('AURA_FROM_EMAIL') ?? 'Aura <hola@somosaurapass.com>'
const PARA = Deno.env.get('AURA_RESUMEN_EMAIL') ?? 'aura.hola.app@gmail.com'
const TRIGGER_SECRET = Deno.env.get('NOTIF_TRIGGER_SECRET') ?? ''

const DIAS = ['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado']

type Nombrado = { nombre?: string; fecha?: string }

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  try {
    if (!TRIGGER_SECRET || req.headers.get('x-notif-secret') !== TRIGGER_SECRET) {
      return json({ error: 'No autorizado' }, 401)
    }
    const body = await req.json().catch(() => ({}))
    const dryRun = body?.dry_run === true
    const testEmail = typeof body?.test_email === 'string' ? body.test_email.trim() : ''
    if (!RESEND_API_KEY && !dryRun) return json({ error: 'RESEND_API_KEY no configurada' }, 500)

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)
    const { data, error } = await admin.rpc('resumen_diario_preparar')
    if (error) return json({ error: 'No se pudieron calcular los números', detalle: error.message }, 500)

    const numero = Number(data?.numero ?? 0)
    const fecha = String(data?.fecha ?? '')
    const m = (data?.metricas ?? {}) as Record<string, unknown>

    // Ya salió el de hoy: no se manda de nuevo (el cron puede correr dos veces).
    if (data?.ya_enviado === true && !testEmail && !dryRun) {
      return json({ ok: true, saltado: 'ya_enviado_hoy', numero })
    }

    const asunto = `Aura · Resumen #${numero} · ${fechaLarga(fecha)}`
    const html = render(numero, fecha, m)

    if (dryRun) return json({ ok: true, dry_run: true, numero, asunto, html })

    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: FROM_EMAIL, reply_to: 'aura.hola.app@gmail.com',
        to: testEmail || PARA, subject: asunto, html,
      }),
    })
    if (!res.ok) {
      const t = await res.text()
      return json({ error: 'resend_fallo', detalle: t.slice(0, 300) }, 502)
    }
    const out = await res.json().catch(() => ({}))
    return json({ ok: true, numero, para: testEmail || PARA, resend_id: (out as { id?: string })?.id })
  } catch (e) {
    return json({ error: String(e) }, 500)
  }
})

function fechaLarga(iso: string): string {
  const d = new Date(iso + 'T12:00:00Z')
  if (isNaN(d.getTime())) return iso
  return `${DIAS[d.getUTCDay()]} ${d.getUTCDate()}/${d.getUTCMonth() + 1}`
}

const n = (v: unknown) => Number(v ?? 0)
const lista = (v: unknown): Nombrado[] => Array.isArray(v) ? v as Nombrado[] : []

function render(numero: number, fecha: string, m: Record<string, unknown>): string {
  const sinClases = lista(m.estudios_sin_clases)
  const sinReservas = lista(m.estudios_sin_reservas_nunca)
  const gracia = lista(m.gracia_por_vencer)
  const sinUsar = lista(m.compraron_sin_reservar)
  const reportes = m.reportes_pendientes

  const movimiento: string[] = [
    `<b>${n(m.altas_ayer)}</b> usuarias nuevas ayer · <b>${n(m.altas_mes)}</b> en el mes`,
    `<b>${n(m.reservas_ayer)}</b> reservas ayer` +
      (n(m.reservas_ayer_de_gente_nueva) > 0
        ? ` · <b>${n(m.reservas_ayer_de_gente_nueva)}</b> de gente que nunca había reservado` : ''),
    `<b>${n(m.packs_ayer)}</b> packs ayer · <b>${n(m.packs_mes)}</b> en el mes`,
  ]
  // Las reseñas sólo si hubo: si no, es una línea que dice 0 todos los días.
  if (n(m.resenas_ayer) > 0) movimiento.push(`<b>${n(m.resenas_ayer)}</b> reseñas nuevas`)

  const plata: string[] = [
    `<b>${n(m.creditos_circulacion)}</b> créditos en circulación (lo que debés en clases)`,
  ]
  if (n(m.checkouts_caidos_mes) > 0) {
    plata.push(`<b>${n(m.checkouts_caidos_mes)}</b> checkouts abandonados este mes, contra ${n(m.packs_mes)} compras`)
  }
  if (sinUsar.length) {
    plata.push(`<b>${sinUsar.length}</b> compraron y nunca reservaron: ${nombres(sinUsar)}`)
  }

  const actuar: string[] = []
  if (typeof reportes === 'number' && reportes > 0) {
    actuar.push(`🔴 <b>${reportes}</b> reporte(s) de "la clase no se dio" sin resolver`)
  }
  if (gracia.length) {
    actuar.push('Se les vence la gracia: ' +
      gracia.map((g) => `<b>${esc(g.nombre)}</b> (${diaCorto(g.fecha)})`).join(' · '))
  }
  if (sinClases.length) {
    actuar.push(`<b>${sinClases.length}</b> estudios activos sin clases futuras: ${nombres(sinClases)}`)
  }
  if (sinReservas.length) {
    actuar.push(`<b>${sinReservas.length}</b> estudios nunca tuvieron una reserva: ${nombres(sinReservas)}`)
  }
  if (!actuar.length) actuar.push('Nada pendiente. 🎉')

  return `<!doctype html>
<html lang="es"><body style="margin:0;padding:0;background:#F5F0E8">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F5F0E8;padding:24px 12px">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
             style="max-width:520px;background:#fff;border-radius:16px;padding:26px;font-family:Arial,sans-serif">
        <tr><td>
          <p style="margin:0 0 2px;color:#E8763A;font-size:13px;font-weight:800;letter-spacing:3px">AURA.</p>
          <p style="margin:0 0 20px;color:#8F877F;font-size:13px">Resumen #${numero} · ${fechaLarga(fecha)}</p>
          ${bloque('MOVIMIENTO', movimiento)}
          ${bloque('PLATA', plata)}
          ${bloque('PARA ACTUAR', actuar)}
          <p style="margin:22px 0 0;color:#B8B0A9;font-size:11px;line-height:1.5">
            Los testers de Android y la cuenta de pruebas no cuentan en estos números.<br>
            Si un día no te llega este mail, algo se rompió: los resúmenes van numerados.
          </p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`
}

function bloque(titulo: string, lineas: string[]): string {
  return `<p style="margin:0 0 6px;color:#9A928B;font-size:11px;font-weight:700;letter-spacing:1px">${titulo}</p>
  <ul style="margin:0 0 20px;padding-left:18px;color:#1A1A1A;font-size:14px;line-height:1.7">
    ${lineas.map((l) => `<li>${l}</li>`).join('')}
  </ul>`
}

function nombres(xs: Nombrado[]): string {
  const hasta = xs.slice(0, 6).map((x) => esc(x.nombre)).join(', ')
  return xs.length > 6 ? `${hasta} y ${xs.length - 6} más` : hasta
}

function diaCorto(iso?: string): string {
  if (!iso) return ''
  const p = iso.split('-')
  return p.length === 3 ? `${Number(p[2])}/${Number(p[1])}` : iso
}

function esc(s?: string): string {
  return String(s ?? '').replace(/[<>&]/g, (c) => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;' }[c]!))
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
