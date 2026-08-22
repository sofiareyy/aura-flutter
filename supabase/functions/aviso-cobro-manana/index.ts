// Envía email de aviso de cobro a cada estudio activo.
// Se ejecuta automáticamente el día 4 de cada mes a las 18hs (cron: 0 18 4 * *)
// También puede invocarse manualmente desde el backoffice.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { netoReserva } from '../_shared/liquidacion.ts'
import { corsHeaders } from '../_shared/cors.ts'

const MESES_ES = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
]

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  // ── Modo prueba ───────────────────────────────────────────────────────────
  // Con {"dry_run": true} arma TODO el reporte y devuelve a quién le habría
  // escrito, pero no manda un solo mail. Sirve para verificar la función sin
  // mailear a los estudios reales. El cron postea `{}`, así que el default es
  // false y el comportamiento normal no cambia.
  const payload = await req.json().catch(() => ({})) as Record<string, unknown>
  const dryRun = payload?.dry_run === true

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const resendApiKey = Deno.env.get('RESEND_API_KEY')

  if (!resendApiKey && !dryRun) {
    console.error('aviso-cobro-manana: RESEND_API_KEY no configurada')
    return json({ error: 'RESEND_API_KEY no configurada' }, 500)
  }

  // ── Verificar autorización ────────────────────────────────────────────────
  // Acepta:
  //   1. Bearer <service_role_key>  → cron job de Supabase
  //   2. Bearer <user_jwt>         → admin autenticado desde Flutter
  const authHeader = req.headers.get('Authorization') ?? ''
  const token = authHeader.replace('Bearer ', '').trim()

  const adminSupabase = createClient(supabaseUrl, serviceRoleKey)

  if (token !== serviceRoleKey) {
    // Verificar que sea un admin autenticado
    const userSupabase = createClient(
      supabaseUrl,
      Deno.env.get('SUPABASE_ANON_KEY')!,
    )
    const { data: { user }, error: authError } = await userSupabase.auth.getUser(token)
    if (authError || !user) {
      return json({ error: 'No autorizado' }, 401)
    }
    const { data: adminRow } = await adminSupabase
      .from('admin_users')
      .select('user_id')
      .eq('user_id', user.id)
      .maybeSingle()
    if (!adminRow) {
      return json({ error: 'Sin permisos de admin' }, 403)
    }
  }

  // ── Calcular rango del mes actual ─────────────────────────────────────────
  const now = new Date()
  const year = now.getFullYear()
  const month = now.getMonth() // 0-indexed
  const inicioMes = new Date(year, month, 1).toISOString()
  const finMes = new Date(year, month + 1, 0, 23, 59, 59).toISOString()
  const nombreMes = `${MESES_ES[month]} ${year}`

  // ── Obtener estudios activos ──────────────────────────────────────────────
  // Los datos de cobro (comisiones + valor_credito) viven en la tabla aparte
  // `estudios_datos_cobro`: se separaron de `estudios` para que el CBU y el
  // margen no viajen en el catálogo, que es público. `fecha_inicio_cobro` SI
  // sigue en `estudios`. Se aplana abajo para que _shared/liquidacion.ts reciba
  // exactamente la misma forma de objeto que antes.
  const { data: estudiosRaw, error: estudiosErr } = await adminSupabase
    .from('estudios')
    .select('id, nombre, fecha_inicio_cobro, estudios_datos_cobro(comision_aura, comision_workshop, valor_credito)')
    .eq('activo', true)
    .order('nombre')

  const estudios = (estudiosRaw ?? []).map((e: Record<string, unknown>) => {
    const raw = e.estudios_datos_cobro
    const dc = (Array.isArray(raw) ? raw[0] : raw) as Record<string, unknown> | null | undefined
    return {
      id: e.id,
      nombre: e.nombre,
      fecha_inicio_cobro: e.fecha_inicio_cobro,
      comision_aura: dc?.comision_aura ?? null,
      comision_workshop: dc?.comision_workshop ?? null,
      valor_credito: dc?.valor_credito ?? null,
    }
  })

  if (estudiosErr || !estudios.length) {
    console.error('aviso-cobro-manana: error obteniendo estudios:', estudiosErr?.message)
    return json({ error: 'Error obteniendo estudios', detail: estudiosErr?.message }, 500)
  }

  // ── Obtener todas las reservas del mes de una vez ─────────────────────────
  // OJO: `reservas` NO tiene columna estudio_id. El estudio sale de la clase,
  // igual que en reporte-mensual-estudios. Antes esto pedía `estudio_id` a
  // `reservas` y PostgREST devolvía 42703; como el error no se capturaba, la
  // función seguía con la lista vacía, todos los montos daban 0, el guard de
  // `montoNeto === 0` salteaba a todos los estudios y terminaba con un 200
  // sin haber mandado un solo mail. El cron lo anotaba como éxito.
  const { data: todasReservas, error: reservasErr } = await adminSupabase
    .from('reservas')
    .select('estado, creditos_usados, clase_id, clases!reservas_clase_id_fkey(estudio_id, tipo)')
    // 'ausente' liquida igual: el credito se consumio al reservar y no vuelve.
    // 'completada' es obligatorio: el cron completar-reservas mueve ahi las
    // reservas apenas termina la clase. Sin eso, no se cobraria casi nada.
    .in('estado', ['confirmada', 'presente', 'ausente', 'completada'])
    .gte('created_at', inicioMes)
    .lte('created_at', finMes)

  // Fail-LOUD: si la consulta de reservas rompe, cortamos con 500 en vez de
  // seguir con la lista vacía. El cron registra la falla y se ve.
  if (reservasErr) {
    console.error('aviso-cobro-manana: error obteniendo reservas:', reservasErr.message)
    return json({ error: 'Error obteniendo reservas', detail: reservasErr.message }, 500)
  }

  // Valor global del crédito (fallback si el estudio no tiene el suyo).
  const { data: cfg, error: cfgErr } = await adminSupabase
    .from('configuracion_global')
    .select('valor')
    .eq('clave', 'valor_credito_ars')
    .maybeSingle()
  if (cfgErr) {
    console.error('aviso-cobro-manana: error leyendo valor_credito_ars:', cfgErr.message)
    return json({ error: 'Error leyendo configuracion_global', detail: cfgErr.message }, 500)
  }
  const valorGlobal = parseInt(String(cfg?.valor ?? '1000'), 10) || 1000

  const estudioPorId: Record<number, any> = {}
  for (const e of estudios) estudioPorId[e.id as number] = e

  // Neto por estudio con la MISMA fórmula que las pantallas de plata.
  const netoPorEstudio: Record<number, number> = {}
  const brutoPorEstudio: Record<number, number> = {}
  const reservasPorEstudio: Record<number, number> = {}
  for (const r of (todasReservas ?? [])) {
    const clase = r.clases as { estudio_id?: number; tipo?: string } | null
    const esId = clase?.estudio_id as number
    if (!esId) continue
    const est = estudioPorId[esId]
    const esWorkshop = clase?.tipo === 'workshop'
    netoPorEstudio[esId] = (netoPorEstudio[esId] ?? 0) + netoReserva(
      { estado: r.estado, creditos_usados: r.creditos_usados, esWorkshop },
      est,
      valorGlobal,
    )
    const v = (est?.valor_credito && est.valor_credito > 0)
      ? est.valor_credito : valorGlobal
    brutoPorEstudio[esId] = (brutoPorEstudio[esId] ?? 0) +
      ((r.creditos_usados as number) ?? 0) * v
    reservasPorEstudio[esId] = (reservasPorEstudio[esId] ?? 0) + 1
  }

  // ── Obtener emails de admins de estudios ──────────────────────────────────
  const estudioIds = estudios.map((e) => e.id as number)
  const { data: adminUsers } = await adminSupabase
    .from('usuarios')
    .select('email, estudio_id')
    .in('rol', ['estudio', 'admin_estudio'])
    .in('estudio_id', estudioIds)

  const emailPorEstudio: Record<number, string> = {}
  for (const u of (adminUsers ?? [])) {
    const esId = u.estudio_id as number
    if (esId && u.email && !emailPorEstudio[esId]) {
      emailPorEstudio[esId] = u.email as string
    }
  }

  // ── Enviar emails ─────────────────────────────────────────────────────────
  const resultados: Array<{
    estudio: string
    enviado: boolean
    monto: number
    motivo?: string
  }> = []

  for (const estudio of estudios) {
    const esId = estudio.id as number
    const cantidadReservas = reservasPorEstudio[esId] ?? 0
    const montoNeto = netoPorEstudio[esId] ?? 0

    if (montoNeto === 0) {
      resultados.push({ estudio: estudio.nombre as string, enviado: false, monto: 0, motivo: 'sin_reservas' })
      continue
    }

    const adminEmail = emailPorEstudio[esId]
    if (!adminEmail) {
      resultados.push({ estudio: estudio.nombre as string, enviado: false, monto: montoNeto, motivo: 'sin_email_admin' })
      continue
    }

    const montoBruto = brutoPorEstudio[esId] ?? 0
    const comisionMonto = montoBruto - montoNeto
    // % efectivo (promedio ponderado clases/workshops), derivado de la resta.
    const comisionPct = montoBruto > 0
      ? Math.round((comisionMonto / montoBruto) * 100)
      : 0

    const html = buildEmailHtml({
      nombreEstudio: estudio.nombre as string,
      cantidadReservas,
      montoBruto,
      comisionPct,
      comisionMonto,
      montoNeto,
      nombreMes,
    })

    // Modo prueba: llegamos hasta acá con el HTML ya armado, pero no se manda.
    if (dryRun) {
      resultados.push({
        estudio: estudio.nombre as string,
        enviado: false,
        monto: montoNeto,
        motivo: `dry_run — habria escrito a ${adminEmail}`,
      })
      continue
    }

    try {
      const resendRes = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${resendApiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          from: Deno.env.get('AURA_FROM_EMAIL') ?? 'Aura <hola@somosaurapass.com>',
          reply_to: 'aura.hola.app@gmail.com',
          to: [adminEmail],
          subject: 'Mañana recibís tu pago de Aura 🧡',
          html,
        }),
      })

      if (resendRes.ok) {
        resultados.push({ estudio: estudio.nombre as string, enviado: true, monto: montoNeto })
      } else {
        const errText = await resendRes.text()
        console.error(`aviso-cobro-manana: error Resend para ${estudio.nombre}:`, errText)
        resultados.push({ estudio: estudio.nombre as string, enviado: false, monto: montoNeto, motivo: errText })
      }
    } catch (e) {
      console.error(`aviso-cobro-manana: excepción para ${estudio.nombre}:`, e)
      resultados.push({ estudio: estudio.nombre as string, enviado: false, monto: montoNeto, motivo: String(e) })
    }
  }

  const enviados = resultados.filter((r) => r.enviado).length
  const omitidos = resultados.filter((r) => !r.enviado && r.monto === 0).length
  // En dry_run los que "habrían salido" no son errores: se cuentan aparte.
  const simulados = dryRun
    ? resultados.filter((r) => !r.enviado && r.monto > 0).length
    : 0
  const errores = dryRun
    ? 0
    : resultados.filter((r) => !r.enviado && r.monto > 0).length

  console.log(
    `aviso-cobro-manana${dryRun ? ' [DRY RUN]' : ''}: ${enviados} enviados, ` +
      `${simulados} simulados, ${omitidos} sin reservas, ${errores} errores`,
  )
  return json({ ok: true, dry_run: dryRun, enviados, simulados, omitidos, errores, detalle: resultados })
})

// ── Builder de HTML ───────────────────────────────────────────────────────────

function buildEmailHtml(params: {
  nombreEstudio: string
  cantidadReservas: number
  montoBruto: number
  comisionPct: number
  comisionMonto: number
  montoNeto: number
  nombreMes: string
}): string {
  const { nombreEstudio, cantidadReservas, montoBruto, comisionPct, comisionMonto, montoNeto, nombreMes } = params
  const fmt = (n: number) => `$${n.toLocaleString('es-AR')}`
  const panelUrl = 'https://somosaura.app/estudio/cobros'

  return `<!DOCTYPE html>
<html lang="es">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#F7F5F2;font-family:Arial,sans-serif;">
  <div style="max-width:520px;margin:32px auto;background:#F7F5F2;padding:32px 24px;border-radius:16px;">

    <div style="text-align:center;margin-bottom:28px;">
      <div style="font-size:36px;line-height:1;">🧡</div>
      <div style="font-size:22px;font-weight:700;color:#1A1A1A;margin-top:8px;">Aura</div>
    </div>

    <p style="color:#1A1A1A;font-size:16px;margin:0 0 8px;">Hola <strong>${nombreEstudio}</strong>,</p>
    <p style="color:#5F5953;font-size:15px;line-height:1.6;margin:0 0 28px;">
      Mañana, día 5, te transferimos tu pago de <strong>${nombreMes}</strong>.
    </p>

    <div style="background:#1A1A1A;border-radius:16px;padding:24px;margin-bottom:24px;">
      <div style="color:#9A928B;font-size:11px;font-weight:700;letter-spacing:1px;margin-bottom:16px;text-transform:uppercase;">Resumen del mes</div>

      <div style="color:#F7F5F2;font-size:14px;margin-bottom:14px;">
        ${cantidadReservas} reserva${cantidadReservas !== 1 ? 's' : ''} completada${cantidadReservas !== 1 ? 's' : ''}
      </div>

      <div style="border-top:1px solid #2A2A2A;padding-top:14px;">
        <table style="width:100%;border-collapse:collapse;">
          <tr>
            <td style="color:#9A928B;font-size:14px;padding:4px 0;">Monto bruto</td>
            <td style="color:#F7F5F2;font-size:14px;text-align:right;padding:4px 0;">${fmt(montoBruto)}</td>
          </tr>
          <tr>
            <td style="color:#9A928B;font-size:14px;padding:4px 0;">Comisión Aura (${comisionPct}%)</td>
            <td style="color:#9A928B;font-size:14px;text-align:right;padding:4px 0;">-${fmt(comisionMonto)}</td>
          </tr>
          <tr style="border-top:1px solid #2A2A2A;">
            <td style="color:#F7F5F2;font-size:16px;font-weight:700;padding-top:12px;">TOTAL A RECIBIR</td>
            <td style="color:#E8763A;font-size:18px;font-weight:700;text-align:right;padding-top:12px;">${fmt(montoNeto)}</td>
          </tr>
        </table>
      </div>
    </div>

    <p style="color:#5F5953;font-size:14px;line-height:1.6;margin:0 0 24px;">
      El pago llega a tu CBU/alias antes de las 12hs del día 5.
    </p>

    <div style="text-align:center;margin-bottom:28px;">
      <a href="${panelUrl}" style="display:inline-block;background:#E8763A;color:white;text-decoration:none;padding:14px 32px;border-radius:12px;font-weight:700;font-size:15px;">
        Ver detalle completo en tu panel →
      </a>
    </div>

    <hr style="border:none;border-top:1px solid #E0DBD6;margin:20px 0;">

    <p style="color:#9A928B;font-size:13px;line-height:1.7;text-align:center;margin:0;">
      Cualquier consulta escribinos a
      <a href="mailto:aura.hola.app@gmail.com" style="color:#E8763A;text-decoration:none;">aura.hola.app@gmail.com</a><br>
      <strong style="color:#1A1A1A;">El equipo de Aura 🧡</strong>
    </p>
  </div>
</body>
</html>`
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
