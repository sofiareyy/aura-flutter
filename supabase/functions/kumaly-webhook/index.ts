// Entrada de Kumaly (sistema de turnos de los estudios) — 18/11/2026.
//
// Kumaly nos manda dos tipos de mensaje:
//   · Ocupación:  {estudio_id, inicio, sala, ocupados, cancelada}
//   · Asistencia: {evento: "asistencia", reserva_id, presente, marcado_at?}
//
// Esta función sólo verifica la clave y pasa el cuerpo a la base. Todos los
// controles (estudio integrado, clase única, ventanas de tiempo, gana el
// último) viven en `kumaly_recibir`, que además anota cada mensaje en
// `kumaly_eventos`. Ver supabase/migrations/20261118170000_kumaly.sql.
//
// verify_jwt = false (declarado en config.toml): Kumaly no tiene un JWT de
// Supabase. La autenticación es la clave KUMALY_CLAVE_ENTRADA, que va en el
// header Authorization ("Bearer <clave>" o la clave sola). La clave nunca va
// al repo, que es público.

import { createClient } from 'npm:@supabase/supabase-js@2.57.4'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const CLAVE = (Deno.env.get('KUMALY_CLAVE_ENTRADA') ?? '').trim()
const TOPE_CUERPO = 64 * 1024

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

async function sha256(texto: string): Promise<Uint8Array> {
  return new Uint8Array(
    await crypto.subtle.digest('SHA-256', new TextEncoder().encode(texto)),
  )
}

// Comparación en tiempo constante: se comparan los hashes, que siempre miden
// lo mismo, así el tiempo de respuesta no dice cuántos caracteres acertó.
async function claveValida(recibida: string): Promise<boolean> {
  const [a, b] = await Promise.all([sha256(recibida), sha256(CLAVE)])
  let diff = 0
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i]
  return diff === 0
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'metodo_no_permitido' }, 405)

  // Sin clave configurada no se acepta nada (nunca "cualquier clave sirve").
  if (CLAVE.length < 32) return json({ error: 'no_configurado' }, 503)

  const token = (req.headers.get('authorization') ?? '')
    .replace(/^Bearer\s+/i, '')
    .trim()
  if (!token || !(await claveValida(token))) {
    return json({ error: 'no_autorizado' }, 401)
  }

  const texto = await req.text()
  if (texto.length > TOPE_CUERPO) return json({ error: 'cuerpo_muy_grande' }, 413)

  let payload: unknown
  try {
    payload = JSON.parse(texto)
  } catch {
    return json({ error: 'json_invalido' }, 400)
  }

  const { data, error } = await admin.rpc('kumaly_recibir', { p_payload: payload })
  if (error || !data) {
    console.error('kumaly_recibir falló:', error?.message)
    return json({ error: 'error_interno' }, 500)
  }

  const { http, ...resto } = data as Record<string, unknown> & { http?: number }
  const status = typeof http === 'number' && http >= 200 && http <= 599 ? http : 500
  return json(resto, status)
})
