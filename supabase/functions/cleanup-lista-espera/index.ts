// AURA - Cron: libera pre_confirmadas vencidas de la lista de espera.
//
// Corre cada 15 min (scheduled con pg_cron -> net.http_post). Para cada
// reserva con estado='pre_confirmada' y expires_at < now():
//   1. La libera (release_pre_reserva): borra la pre_confirmada y restaura
//      el lugar en la clase.
//   2. Promueve al siguiente de la lista de espera (lo hace el mismo RPC).
//   3. Inserta una notificación in-app (campanita) para el promovido.
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

  // Fail-CLOSED: si no está configurado CRON_SECRET, se rechaza. Antes, sin
  // el secret, la función aceptaba cualquier POST.
  if (!CRON_SECRET) {
    console.error('CRON_SECRET no configurado; rechazando')
    return json({ ok: false, error: 'No configurado' }, 503)
  }
  {
    const provided =
      req.headers.get('x-cron-secret') ??
      (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '')
    if (provided !== CRON_SECRET) {
      return json({ ok: false, error: 'No autorizado' }, 401)
    }
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)

  try {
    // 1. Buscar pre_confirmadas vencidas.
    const { data: expiradas, error } = await admin
      .from('reservas')
      .select('id, clase_id')
      .eq('estado', 'pre_confirmada')
      .lt('expires_at', new Date().toISOString())

    if (error) throw error

    let liberadas = 0
    let promovidos = 0
    const notifs: Array<Record<string, unknown>> = []

    for (const r of expiradas ?? []) {
      // Libera la vencida y promueve al siguiente (RPC devuelve los promovidos).
      const { data: rel, error: relErr } = await admin.rpc(
        'release_pre_reserva',
        { p_reserva_id: r.id },
      )
      if (relErr) {
        console.error('release_pre_reserva error', r.id, relErr)
        continue
      }
      liberadas++

      // rel = { ok, clase_id, promoted: { ok, promoted: [ {...} ] } }
      const promotedList = (rel as { promoted?: { promoted?: unknown[] } })
        ?.promoted?.promoted
      if (Array.isArray(promotedList)) {
        for (const p of promotedList) {
          const prom = p as {
            usuario_id?: string
            clase_nombre?: string
          }
          promovidos++
          if (prom.usuario_id) {
            const claseNombre = prom.clase_nombre ?? 'una clase'
            notifs.push({
              usuario_id: prom.usuario_id,
              titulo: '¡Se liberó un lugar! ⚡',
              mensaje:
                `¡Se liberó un lugar en ${claseNombre}! ` +
                'Tenés 30 minutos para confirmar.',
              tipo: 'pre_confirmada',
              leida: false,
            })
          }
        }
      }
    }

    // 3. Notificar in-app a los promovidos (bulk).
    if (notifs.length > 0) {
      const { error: nErr } = await admin
        .from('notificaciones_usuario')
        .insert(notifs)
      if (nErr) console.error('notificaciones_usuario insert error', nErr)
    }

    return json({
      ok: true,
      liberadas,
      promovidos,
      notificados: notifs.length,
    })
  } catch (e) {
    console.error('cleanup-lista-espera error', e)
    return json({ ok: false, error: String(e) }, 500)
  }
})
