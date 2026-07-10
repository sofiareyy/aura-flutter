// AURA - Cron: regenera las clases concretas a partir de los horarios fijos.
//
// Corre 1 vez por día (00:00 ART). Llama al RPC generar_clases_todos_estudios
// que, para cada estudio con horarios fijos activos, genera las clases de las
// próximas N semanas (default 4) sin duplicar las ya existentes (tolerancia
// ±1h). Así la grilla nunca se agota aunque el estudio no abra la app.
//
// Seguridad: verify_jwt=false + chequeo de CRON_SECRET (header x-cron-secret).
// Usa el service role internamente (bypassa RLS).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const CRON_SECRET = Deno.env.get('CRON_SECRET') ?? ''

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (CRON_SECRET) {
    const provided =
      req.headers.get('x-cron-secret') ??
      (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '')
    if (provided !== CRON_SECRET) {
      return json({ ok: false, error: 'No autorizado' }, 401)
    }
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)

  try {
    // Semanas a generar hacia adelante (default 4, override por body/query).
    let weeks = 4
    try {
      const url = new URL(req.url)
      const qp = url.searchParams.get('weeks')
      if (qp) weeks = parseInt(qp, 10)
      if (req.method === 'POST') {
        const body = await req.json().catch(() => null)
        if (body && typeof body.weeks === 'number') weeks = body.weeks
      }
    } catch (_) {
      // Ignorar parseo: usamos el default.
    }
    if (!Number.isFinite(weeks) || weeks < 1) weeks = 4

    const { data, error } = await admin.rpc('generar_clases_todos_estudios', {
      p_weeks: weeks,
    })
    if (error) throw error

    return json({ ok: true, weeks, resultado: data })
  } catch (e) {
    console.error('regenerar-grillas error', e)
    return json({ ok: false, error: String(e) }, 500)
  }
})
