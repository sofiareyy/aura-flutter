// Aviso inmediato a Aura cuando alguien compra.
//
// Por qué existe: hasta el 4/10/2026 una compra sólo se sabía por la línea
// del resumen del día siguiente ("1 pack ayer"). Con pocas compras por
// semana, cada una importa y enterarse 11 horas después es tarde.
//
// Es una función INTERNA, igual que email-regalo: la llama el mp-webhook con
// el service_role. Recibe sólo el id del pago y lee el resto de la base, así
// el webhook queda fino y el aviso se puede reenviar a mano con un solo dato.
//
// Best-effort: si el mail falla, la compra YA está acreditada. Nunca tira
// para arriba — un aviso perdido no puede romper un pago.

import { corsHeaders } from '../_shared/cors.ts'

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? ''
const FROM_EMAIL =
  Deno.env.get('AURA_FROM_EMAIL') ?? 'Aura <hola@somosaurapass.com>'
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
// La misma casilla que el resumen diario, y por la misma variable: si algún
// día se cambia, los dos avisos se mudan juntos.
const PARA = Deno.env.get('AURA_RESUMEN_EMAIL') ?? 'aura.hola.app@gmail.com'

const money = (n: number) =>
  '$' + Math.round(n).toLocaleString('es-AR')

const esc = (s: string) =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const auth = req.headers.get('Authorization') ?? ''
    if (!SERVICE_ROLE_KEY || auth !== `Bearer ${SERVICE_ROLE_KEY}`) {
      return json({ error: 'No autorizado' }, 401)
    }
    if (!RESEND_API_KEY) {
      return json({ error: 'RESEND_API_KEY no configurada' }, 500)
    }

    const body = await req.json().catch(() => null)
    const pagoId = body?.pago_id
    const testEmail: string | undefined = body?.test_email
    if (pagoId == null) {
      return json({ error: 'Falta pago_id' }, 400)
    }

    const pago = await traer(
      `/rest/v1/pagos?id=eq.${pagoId}&select=id,type,status,amount,creditos,pack_nombre,plan_nombre,gift_email,created_at,user_id`,
    )
    const p = pago?.[0]
    if (!p) return json({ error: 'Pago no encontrado' }, 404)

    const usuario = await traer(
      `/rest/v1/usuarios?id=eq.${p.user_id}&select=nombre,email,creditos`,
    )
    const u = usuario?.[0] ?? {}

    // Cuántas compras lleva: separa a la que vuelve de la que estrena.
    const previas = await traer(
      `/rest/v1/pagos?user_id=eq.${p.user_id}&status=eq.approved&select=id`,
    )
    const cuantas = Array.isArray(previas) ? previas.length : 1

    const quien = (u.nombre ?? '').trim() || (u.email ?? 'Alguien')
    const que = p.pack_nombre ?? p.plan_nombre ??
      (p.type === 'plan' ? 'una suscripción' : 'un pack')
    const monto = Number(p.amount ?? 0)
    const creditos = Number(p.creditos ?? 0)
    const esRegalo = Boolean(p.gift_email)

    const asunto = `💸 ${quien} compró ${que} · ${money(monto)}`

    const html = `
<div style="font-family:system-ui,-apple-system,'Segoe UI',sans-serif;max-width:520px;margin:0 auto;padding:24px;color:#1A1A1A">
  <div style="font-size:13px;letter-spacing:1px;color:#8A8A8A;font-weight:700">COMPRA NUEVA</div>
  <div style="font-size:30px;font-weight:700;margin:10px 0 2px">${money(monto)}</div>
  <div style="font-size:16px;color:#5A534D;margin-bottom:20px">${esc(que)}${
      creditos > 0 ? ` · ${creditos} créditos` : ''
    }</div>
  <table style="width:100%;border-collapse:collapse;font-size:15px">
    <tr><td style="padding:8px 0;color:#8A8A8A">Quién</td><td style="padding:8px 0;text-align:right;font-weight:600">${
      esc(quien)
    }</td></tr>
    <tr><td style="padding:8px 0;color:#8A8A8A">Mail</td><td style="padding:8px 0;text-align:right">${
      esc(u.email ?? '—')
    }</td></tr>
    <tr><td style="padding:8px 0;color:#8A8A8A">Compras</td><td style="padding:8px 0;text-align:right">${
      cuantas === 1 ? 'la primera 🎉' : `la número ${cuantas}`
    }</td></tr>
    <tr><td style="padding:8px 0;color:#8A8A8A">Saldo ahora</td><td style="padding:8px 0;text-align:right">${
      Number(u.creditos ?? 0)
    } créditos</td></tr>${
      esRegalo
        ? `
    <tr><td style="padding:8px 0;color:#8A8A8A">Regalo para</td><td style="padding:8px 0;text-align:right">${
          esc(p.gift_email)
        }</td></tr>`
        : ''
    }
  </table>
</div>`

    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: FROM_EMAIL,
        reply_to: 'aura.hola.app@gmail.com',
        to: testEmail || PARA,
        subject: asunto,
        html,
      }),
    })

    if (!res.ok) {
      const detalle = await res.text()
      console.error('compra-aviso: Resend falló:', detalle)
      return json({ error: 'Resend falló', detalle }, 502)
    }

    return json({ ok: true, para: testEmail || PARA, asunto })
  } catch (e) {
    console.error('compra-aviso: excepción', e)
    return json({ error: String(e) }, 500)
  }
})

async function traer(path: string) {
  const res = await fetch(`${SUPABASE_URL}${path}`, {
    headers: {
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    },
  })
  if (!res.ok) return null
  return await res.json().catch(() => null)
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
