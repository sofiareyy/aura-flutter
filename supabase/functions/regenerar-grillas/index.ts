// AURA - Cron: regenera las clases concretas a partir de los horarios fijos.
//
// Corre 1 vez por día (00:00 ART). Llama al RPC generar_clases_todos_estudios
// que, para cada estudio con horarios fijos activos, genera las clases de las
// próximas N semanas (default 4) sin duplicar las ya existentes (tolerancia
// ±1h). Así la grilla nunca se agota aunque el estudio no abra la app.
//
// Seguridad: verify_jwt=false + validación del service_role en el header.
// Usa el service role internamente (bypassa RLS).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

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

  // Auth: el cron manda el service_role en el Authorization. verify_jwt está
  // en false, así que se valida a mano. Fail-CLOSED: sin service_role válido,
  // 401. Ya no depende de CRON_SECRET.
  {
    const token = (req.headers.get('Authorization') ?? '')
      .replace(/^Bearer\s+/i, '')
      .trim()
    if (token !== SERVICE_ROLE_KEY) {
      return json({ ok: false, error: 'No autorizado' }, 401)
    }
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)

  try {
    // Ventana de grilla: 9 semanas = 63 dias. Antes el cron mantenia 4
    // semanas y el boton del panel generaba 13, asi que el estudio veia una
    // ventana y el cron otra.
    const SEMANAS_GRILLA = 9
    // Semanas a generar hacia adelante (override por body/query).
    let weeks = SEMANAS_GRILLA
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
    // Piso en 9: el cron ya agendado en el dashboard manda `weeks: 4` en el
    // body. En vez de pisar ese cron (no tenemos sus placeholders), lo
    // tratamos como minimo garantizado. Mandar mas de 9 sigue funcionando.
    if (!Number.isFinite(weeks) || weeks < SEMANAS_GRILLA) {
      weeks = SEMANAS_GRILLA
    }

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
