// resend-webhook — Resend avisa acá cada vez que un mail rebota o alguien lo
// marca como spam, y la dirección queda en `mail_bajas` para siempre.
//
// Pedido de Sofía (3/11/2026): "si una dirección rebota una vez, que no se le
// vuelva a mandar nunca". Todos los envíos que no son avisos de una reserva o
// un pago (regalos, invitaciones, secuencia de bienvenida) miran mail_bajas
// antes de salir, así que no hace falta tocar nada más.
//
// Cubre TODOS los mails de Aura, no solo las campañas: si un aviso de reserva
// rebota, esa dirección tampoco recibe campañas.
//
// Excepción: las direcciones @privaterelay.appleid.com. Rebotan si Aura no
// está registrada en el relay de Apple (configuración nuestra, no cuenta
// falsa); se anotan con origen 'rebote_apple' para poder liberarlas cuando se
// registre el dominio.
//
// Seguridad: verify_jwt = false (Resend no manda JWT). Lo que autoriza es la
// firma de Svix (headers svix-id, svix-timestamp, svix-signature) con
// RESEND_WEBHOOK_SECRET. Sin firma válida, 401.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { verificarFirmaSvix } from '../_shared/svix.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const SECRETO = Deno.env.get('RESEND_WEBHOOK_SECRET') ?? ''

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json({ error: 'Usá POST' }, 405)
  if (!SECRETO) return json({ error: 'RESEND_WEBHOOK_SECRET no configurado' }, 500)

  const cuerpo = await req.text()
  const ok = await verificarFirmaSvix({
    secreto: SECRETO,
    id: req.headers.get('svix-id') ?? '',
    timestamp: req.headers.get('svix-timestamp') ?? '',
    firmas: req.headers.get('svix-signature') ?? '',
    cuerpo,
  })
  if (!ok) return json({ error: 'Firma inválida' }, 401)

  let evento: { type?: string; data?: { to?: string[] | string } }
  try {
    evento = JSON.parse(cuerpo)
  } catch (_) {
    return json({ error: 'JSON inválido' }, 400)
  }

  const tipo = String(evento.type ?? '')
  if (tipo !== 'email.bounced' && tipo !== 'email.complained') {
    return json({ ok: true, ignorado: tipo })   // otros eventos no nos importan
  }

  const destinos = (Array.isArray(evento.data?.to) ? evento.data!.to : [evento.data?.to])
    .filter((x): x is string => typeof x === 'string' && x.includes('@'))
    .map((x) => x.trim().toLowerCase())

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)
  const filas = []
  for (const email of destinos) {
    const origen = tipo === 'email.complained'
      ? 'queja'
      : (email.endsWith('@privaterelay.appleid.com') ? 'rebote_apple' : 'rebote')
    const { data: u } = await admin.from('usuarios').select('id').eq('email', email).maybeSingle()
    filas.push({ email, usuario_id: u?.id ?? null, origen })
  }
  if (filas.length) {
    // ignoreDuplicates: si ya estaba (por baja o rebote anterior), queda como estaba.
    const { error } = await admin.from('mail_bajas').upsert(filas, { onConflict: 'email', ignoreDuplicates: true })
    if (error) return json({ error: 'No se pudo guardar', detalle: error.message }, 500)
  }
  return json({ ok: true, tipo, anotadas: filas.map((f) => `${f.email} (${f.origen})`) })
})

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
}
