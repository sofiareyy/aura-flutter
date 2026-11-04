// pago-estudio-email — "Ya te transferimos" al estudio (4/11/2026).
//
// Dos maneras de llamarla:
//   · El trigger trg_liquidacion_pagada_mail, cuando una liquidación pasa a
//     'pagado'. Header x-notif-secret. Sale UNA sola vez (mail_pago_at).
//   · El botón "Reenviar mail de pago" del backoffice. JWT de un admin de Aura
//     (is_admin). Body {liquidacion_id, reenvio: true}. Sale siempre, con el
//     monto efectivo (fila + asientos de corrección) y el aviso de que
//     reemplaza al anterior.
// Prueba: {liquidacion_id, test_email} manda solo a esa casilla y no registra nada.
//
// Destinatarios: los admins del estudio (sin profes), menos las cuentas
// internas de Aura, menos las cuentas personales de Sofía y menos las que
// rebotaron (mail_bajas con origen de rebote o queja). Es un aviso del
// servicio: no lleva link de baja.
// Copia oculta: aura.hola.app recibe todos, para chequear que salen bien.
//
// Sin número de operación no sale (pedido de Sofía, 4/11): el estudio no
// podría verificar la transferencia. La base tampoco deja marcar un pago sin él.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { htmlATexto, REPLY_TO } from '../_shared/email.ts'
import { armarMailPago, type OtraSede } from './mail.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? ''
const TRIGGER_SECRET = Deno.env.get('NOTIF_TRIGGER_SECRET') ?? ''
const FROM_EMAIL = Deno.env.get('AURA_FROM_EMAIL') ?? 'Aura <hola@somosaurapass.com>'

const COPIA_AURA = 'aura.hola.app@gmail.com'
// Cuentas de Sofía que figuran como admins de estudios y no deben recibir avisos de pago.
const NO_RECIBEN = new Set(['sofi.rey.2000@gmail.com', 'reysofia19@gmail.com'])

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-notif-secret',
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  try {
    if (!RESEND_API_KEY) return json({ error: 'RESEND_API_KEY no configurada' }, 500)

    // ── Quién llama ───────────────────────────────────────────────────────
    const desdeTrigger = !!TRIGGER_SECRET && req.headers.get('x-notif-secret') === TRIGGER_SECRET
    if (!desdeTrigger) {
      const auth = req.headers.get('Authorization') ?? ''
      const comoUsuario = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: auth } } })
      const { data: esAdmin } = await comoUsuario.rpc('is_admin')
      if (esAdmin !== true) return json({ error: 'No autorizado' }, 401)
    }

    const body = await req.json().catch(() => null)

    // {"consultar_mes": "YYYY-MM"}: qué dice Resend de cada mail de pago de ese mes.
    if (typeof body?.consultar_mes === 'string' && body.consultar_mes) {
      const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)
      const { data: filas } = await admin.from('liquidaciones')
        .select('mail_pago_id, estudios(nombre)').eq('mes', body.consultar_mes).not('mail_pago_id', 'is', null)
      const resultados: { estudio: string; evento: string }[] = []
      for (const f of filas ?? []) {
        const r = await fetch(`https://api.resend.com/emails/${f.mail_pago_id}`, {
          headers: { 'Authorization': `Bearer ${RESEND_API_KEY}` },
        })
        const d = await r.json().catch(() => ({})) as { last_event?: string }
        resultados.push({
          estudio: (f as { estudios?: { nombre?: string } }).estudios?.nombre ?? '?',
          evento: r.ok ? String(d.last_event ?? 'desconocido') : `error_${r.status}`,
        })
        await new Promise((res) => setTimeout(res, 600))
      }
      return json({ ok: true, resultados })
    }

    const liqId = String(body?.liquidacion_id ?? '')
    if (!liqId) return json({ error: 'Falta liquidacion_id' }, 400)
    const reenvio = body?.reenvio === true
    if (reenvio && desdeTrigger) return json({ error: 'El reenvío es solo a mano' }, 400)
    const testEmail = typeof body?.test_email === 'string' ? body.test_email.trim().toLowerCase() : ''

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)
    const { data: l } = await admin.from('liquidaciones')
      .select('id, estudio_id, mes, estado, monto_a_pagar, cantidad_reservas, numero_operacion, mail_pago_at, mail_pago_envios, liquidaciones_correcciones(diferencia)')
      .eq('id', liqId).maybeSingle()
    if (!l) return json({ error: 'Liquidación no encontrada' }, 404)
    if (l.estado !== 'pagado') return json({ error: 'La liquidación no está pagada' }, 400)

    const numero = (l.numero_operacion ?? '').trim() || null
    if (!numero) return json({ ok: false, error: 'sin_numero_operacion' }, 400)

    // El automático sale una sola vez. Se reserva la fila antes de mandar,
    // para que dos disparos a la vez no manden dos mails.
    if (!reenvio && !testEmail) {
      const { data: tomada } = await admin.from('liquidaciones')
        .update({ mail_pago_at: new Date().toISOString() })
        .eq('id', liqId).is('mail_pago_at', null).select('id')
      if (!tomada || tomada.length === 0) return json({ ok: true, enviados: 0, motivo: 'ya_enviado' })
    }

    const monto = montoEfectivo(l)
    const { data: estudio } = await admin.from('estudios').select('nombre').eq('id', l.estudio_id).maybeSingle()

    // Otras sedes pagadas con la misma transferencia (mismo mes y número).
    const otrasSedes: OtraSede[] = []
    {
      const { data: otras } = await admin.from('liquidaciones')
        .select('id, estudio_id, monto_a_pagar, liquidaciones_correcciones(diferencia), estudios(nombre)')
        .eq('mes', l.mes).eq('estado', 'pagado').eq('numero_operacion', numero).neq('id', l.id)
      for (const o of otras ?? []) {
        const nombre = (o as { estudios?: { nombre?: string } }).estudios?.nombre ?? 'otra sede'
        otrasSedes.push({ nombre, monto: montoEfectivo(o) })
      }
    }

    const destinatarios = testEmail ? [testEmail] : await destinatariosDe(admin, l.estudio_id)
    if (destinatarios.length === 0) return json({ ok: true, enviados: 0, motivo: 'sin_destinatarios' })

    const { subject, html } = armarMailPago({
      estudio: estudio?.nombre ?? 'tu estudio', mes: l.mes, monto,
      reservas: Number(l.cantidad_reservas ?? 0), numeroOperacion: numero, otrasSedes, reenvio,
    })
    const r = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: FROM_EMAIL, reply_to: REPLY_TO, to: destinatarios,
        ...(testEmail ? {} : { bcc: [COPIA_AURA] }),
        subject, html, text: htmlATexto(html),
      }),
    })
    const d = await r.json().catch(() => ({})) as { id?: string; message?: string }

    if (testEmail) return json({ ok: r.ok, test: true, subject, destinatarios, id: d.id, error: d.message })

    if (!r.ok) {
      // Si falló el automático, se libera para poder reintentar con el botón.
      if (!reenvio) await admin.from('liquidaciones').update({ mail_pago_at: null }).eq('id', liqId)
      return json({ ok: false, error: d.message ?? `Resend ${r.status}` }, 502)
    }
    await admin.from('liquidaciones').update({
      mail_pago_at: new Date().toISOString(),
      mail_pago_id: d.id ?? null,
      mail_pago_envios: Number(l.mail_pago_envios ?? 0) + 1,
    }).eq('id', liqId)
    return json({ ok: true, enviados: destinatarios.length, destinatarios, monto, subject })
  } catch (e) {
    return json({ error: String(e) }, 500)
  }
})

function montoEfectivo(l: { monto_a_pagar?: number | null; liquidaciones_correcciones?: { diferencia?: number | null }[] | null }): number {
  const base = Number(l.monto_a_pagar ?? 0)
  return base + (l.liquidaciones_correcciones ?? []).reduce((a, c) => a + Number(c.diferencia ?? 0), 0)
}

// deno-lint-ignore no-explicit-any
async function destinatariosDe(admin: any, estudioId: number): Promise<string[]> {
  const { data: admins } = await admin.from('estudio_admins')
    .select('usuario_id').eq('estudio_id', estudioId).neq('rol', 'profe')
  const emails: string[] = []
  for (const a of admins ?? []) {
    const { data: u } = await admin.auth.admin.getUserById(String(a.usuario_id))
    const email = u?.user?.email?.trim().toLowerCase()
    if (!email || !email.includes('@') || email.endsWith('@cuenta-eliminada.aura')) continue
    if (NO_RECIBEN.has(email) || email === COPIA_AURA) continue
    const { data: interna } = await admin.from('cuentas_internas').select('email').eq('email', email).maybeSingle()
    if (interna) continue
    const { data: baja } = await admin.from('mail_bajas').select('origen').eq('email', email).maybeSingle()
    if (baja && ['rebote', 'rebote_apple', 'queja'].includes(String(baja.origen))) continue
    emails.push(email)
  }
  return [...new Set(emails)]
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}
