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
    // En dry_run se RECALCULA (p_solo_calcular) en vez de leer lo guardado:
    // si no, probar el mail después del envío del día devuelve las métricas
    // viejas y una métrica nueva aparece en cero.
    const { data, error } = await admin.rpc('resumen_diario_preparar',
      dryRun ? { p_solo_calcular: true } : {})
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

  // ── Movimiento ────────────────────────────────────────────────────────
  const movimiento: string[] = [
    `<b>${n(m.altas_mes)}</b> usuarias nuevas en lo que va del mes`,
    `<b>${n(m.packs_ayer)}</b> packs ayer · <b>${n(m.packs_mes)}</b> en el mes`,
  ]
  if (n(m.reservas_ayer_de_gente_nueva) > 0) {
    movimiento.unshift(`<b>${n(m.reservas_ayer_de_gente_nueva)}</b> de las reservas de ayer son de gente que nunca había reservado`)
  }
  // Las reseñas sólo si hubo: si no, es una línea que dice 0 todos los días.
  if (n(m.resenas_ayer) > 0) movimiento.push(`<b>${n(m.resenas_ayer)}</b> reseñas nuevas`)

  // ── Estudios: el panorama, no sólo lo que falta ───────────────────────
  const estudios: string[] = [
    `<b>${n(m.estudios_activos)}</b> activos de <b>${n(m.estudios_total)}</b> en total`,
    `<b>${n(m.estudios_con_clases)}</b> con clases cargadas · <b>${sinClases.length}</b> sin ninguna clase futura`,
  ]
  if (sinClases.length) estudios.push(`Sin clases: ${nombres(sinClases)}`)

  // ── Plata ─────────────────────────────────────────────────────────────
  const plata: string[] = []
  if (n(m.checkouts_caidos_mes) > 0) {
    plata.push(`<b>${n(m.checkouts_caidos_mes)}</b> checkouts abandonados este mes, contra ${n(m.packs_mes)} compras`)
  }
  if (sinUsar.length) {
    plata.push(`<b>${sinUsar.length}</b> compraron y nunca reservaron: ${nombres(sinUsar)}`)
  }
  if (!plata.length) plata.push('Sin movimientos para revisar.')

  // ── Para actuar ───────────────────────────────────────────────────────
  const actuar: string[] = []
  if (typeof reportes === 'number' && reportes > 0) {
    actuar.push(`<b style="color:#C4562A">${reportes} reporte(s) de "la clase no se dio" sin resolver</b>`)
  }
  if (gracia.length) {
    actuar.push('Se les vence la gracia: ' +
      gracia.map((g) => `<b>${esc(g.nombre)}</b> (${diaCorto(g.fecha)})`).join(' · '))
  }
  if (sinReservas.length) {
    actuar.push(`<b>${sinReservas.length}</b> estudios nunca tuvieron una reserva: ${nombres(sinReservas)}`)
  }
  if (!actuar.length) actuar.push('Nada pendiente. 🎉')

  return `<!doctype html>
<html lang="es"><body style="margin:0;padding:0;background:#EFE9E1">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#EFE9E1;padding:32px 14px">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
             style="max-width:560px;background:#ffffff;border-radius:20px;font-family:Arial,Helvetica,sans-serif">

        <!-- Encabezado -->
        <tr><td style="padding:34px 36px 26px">
          <p style="margin:0 0 6px;color:#E8763A;font-size:14px;font-weight:800;letter-spacing:4px">AURA.</p>
          <p style="margin:0;color:#1A1A1A;font-size:20px;font-weight:700;line-height:1.3">Resumen #${numero}</p>
          <p style="margin:4px 0 0;color:#9A928B;font-size:14px">${fechaLarga(fecha)}</p>
        </td></tr>

        <!-- Los tres números que se leen de un golpe -->
        <tr><td style="padding:0 24px 8px">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
            <tr>
              ${destacado(n(m.altas_ayer), 'usuarias nuevas', 'ayer')}
              ${destacado(n(m.reservas_ayer), 'reservas', 'ayer')}
              ${destacado(n(m.creditos_circulacion), 'créditos', 'en circulación')}
            </tr>
          </table>
        </td></tr>

        ${bloque('MOVIMIENTO', movimiento)}
        ${bloque('ESTUDIOS', estudios)}
        ${bloque('PLATA', plata)}
        ${bloque('PARA ACTUAR', actuar, true)}

        <tr><td style="padding:8px 36px 34px">
          <p style="margin:0;color:#B8B0A9;font-size:11px;line-height:1.7">
            Los testers de Android y la cuenta de pruebas no cuentan en estos números.<br>
            Si un día no te llega este mail, algo se rompió: los resúmenes van numerados.
          </p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`
}

/** Un número grande con su etiqueta abajo. */
function destacado(valor: number, etiqueta: string, detalle: string): string {
  return `<td width="33%" align="center" style="padding:14px 6px">
    <div style="background:#FAF7F3;border-radius:14px;padding:18px 8px">
      <div style="color:#1A1A1A;font-size:34px;font-weight:800;line-height:1">${valor}</div>
      <div style="color:#5E584F;font-size:12px;font-weight:700;margin-top:8px">${etiqueta}</div>
      <div style="color:#9A928B;font-size:11px;margin-top:2px">${detalle}</div>
    </div>
  </td>`
}

/** Un bloque con su título separado del contenido por una línea. */
function bloque(titulo: string, lineas: string[], destacar = false): string {
  const color = destacar ? '#C4562A' : '#9A928B'
  return `<tr><td style="padding:18px 36px 0">
    <p style="margin:0 0 10px;color:${color};font-size:11px;font-weight:800;letter-spacing:1.6px">${titulo}</p>
    <div style="border-top:1px solid #EDE7E1;padding-top:14px">
      ${lineas.map((l) => `<p style="margin:0 0 10px;color:#1A1A1A;font-size:14px;line-height:1.65">${l}</p>`).join('')}
    </div>
  </td></tr>`
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
