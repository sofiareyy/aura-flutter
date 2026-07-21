// AURA - Cron: acredita los créditos mensuales de los usuarios corporativos.
//
// Corre 1 vez por mes (día 1, 00:00 ART). Llama al RPC
// acreditar_creditos_corporativos, que recorre las empresas activas y acredita
// los créditos del beneficio a cada empleado corporativo (fuente 'corporativo').
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
    const { data, error } = await admin.rpc('acreditar_creditos_corporativos')
    if (error) throw error

    console.log('acreditar-creditos-corporativos:', JSON.stringify(data))
    return json({ ok: true, resultado: data })
  } catch (e) {
    console.error('acreditar-creditos-corporativos error', e)
    return json({ ok: false, error: String(e) }, 500)
  }
})
