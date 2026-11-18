// Salida hacia Kumaly (sistema de turnos de los estudios) — 18/11/2026.
//
// La llama el cron `kumaly-enviar` cada minuto, y sólo cuando hay algo
// pendiente en `kumaly_envios`. Toma lo que toca mandar con
// `kumaly_tomar_envios` (que además cierra lo vencido) y anota cada
// respuesta con `kumaly_registrar_respuesta`:
//   · 2xx           → confirmado
//   · 409 sin_lugar → la base cancela la reserva, devuelve y avisa
//   · otra cosa     → se reintenta a los 10 min, hasta el límite
// Ver supabase/migrations/20261118170000_kumaly.sql.
//
// SECRETOS (nunca en el repo, que es público):
//   · KUMALY_URL          adónde mandamos los mensajes (la pasa Kumaly)
//   · KUMALY_CLAVE_SALIDA la clave de este sentido (la pasa Kumaly). Va en el
//                         header Authorization: si el valor ya empieza con
//                         "Bearer " o "Basic " se manda tal cual; si no, con
//                         "Bearer " adelante.
// Si falta alguno, la función no toca NADA: ni manda ni da por vencido.
// Así un olvido de configuración nunca cancela reservas.

import { createClient } from 'npm:@supabase/supabase-js@2.57.4'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const KUMALY_URL = (Deno.env.get('KUMALY_URL') ?? '').trim()
const KUMALY_CLAVE = (Deno.env.get('KUMALY_CLAVE_SALIDA') ?? '').trim()

/// Tope para la respuesta de Kumaly. Si no contesta a tiempo, se reintenta.
const TOPE_MS = 10_000
const LOTE = 20

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

function headerAutorizacion(): string {
  return /^(Bearer|Basic)\s/i.test(KUMALY_CLAVE) ? KUMALY_CLAVE : `Bearer ${KUMALY_CLAVE}`
}

async function mandar(payload: unknown): Promise<{ status: number; cuerpo: string }> {
  try {
    const res = await fetch(KUMALY_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': headerAutorizacion(),
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(TOPE_MS),
    })
    const cuerpo = await res.text().catch(() => '')
    return { status: res.status, cuerpo: cuerpo.slice(0, 2000) }
  } catch (e) {
    // Sin respuesta (caído, tiempo agotado, DNS): status 0 = reintentar.
    return { status: 0, cuerpo: `sin respuesta: ${(e as Error)?.message ?? e}` }
  }
}

Deno.serve(async (req) => {
  const bearer = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '').trim()
  if (bearer !== SERVICE_ROLE_KEY) return json({ error: 'no_autorizado' }, 401)

  if (!KUMALY_URL || !KUMALY_CLAVE) {
    return json({ error: 'no_configurado', falta: { KUMALY_URL: !KUMALY_URL, KUMALY_CLAVE_SALIDA: !KUMALY_CLAVE } }, 503)
  }

  const { data: envios, error } = await admin.rpc('kumaly_tomar_envios', { p_lote: LOTE })
  if (error) {
    console.error('kumaly_tomar_envios falló:', error.message)
    return json({ error: 'error_interno' }, 500)
  }

  const resultados: Array<Record<string, unknown>> = []
  // De a uno y en orden: la cancelación de una reserva nunca sale antes que
  // la reserva (además, la base sólo la entrega cuando la reserva ya está
  // confirmada).
  for (const e of (envios ?? []) as Array<{ id: number; evento: string; payload: unknown }>) {
    const { status, cuerpo } = await mandar(e.payload)
    const { data: r, error: errReg } = await admin.rpc('kumaly_registrar_respuesta', {
      p_id: e.id,
      p_status: status,
      p_cuerpo: cuerpo,
    })
    if (errReg) console.error('kumaly_registrar_respuesta falló:', e.id, errReg.message)
    resultados.push({ id: e.id, evento: e.evento, status, estado: (r as { estado?: string } | null)?.estado ?? null })
  }

  return json({ ok: true, mandados: resultados.length, resultados })
})
