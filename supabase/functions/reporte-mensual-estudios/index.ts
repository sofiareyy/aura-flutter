// Envía reporte mensual de estadísticas a cada estudio activo.
// Puede invocarse manualmente desde el backoffice.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { netoReserva, valorCredito as valorCred } from '../_shared/liquidacion.ts'
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
  // Con {"dry_run": true} arma TODO el reporte y devuelve a quien le habria
  // escrito, pero no manda un solo mail. El cron postea `{}`, asi que el
  // default es false y el comportamiento normal no cambia.
  const payload = await req.json().catch(() => ({})) as Record<string, unknown>
  const dryRun = payload?.dry_run === true

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const resendApiKey = Deno.env.get('RESEND_API_KEY')

  if (!resendApiKey && !dryRun) {
    console.error('reporte-mensual-estudios: RESEND_API_KEY no configurada')
    return json({ error: 'RESEND_API_KEY no configurada' }, 500)
  }

  // ── Verificar autorización ────────────────────────────────────────────────
  const authHeader = req.headers.get('Authorization') ?? ''
  const token = authHeader.replace('Bearer ', '').trim()

  const adminSupabase = createClient(supabaseUrl, serviceRoleKey)

  if (token !== serviceRoleKey) {
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

  // ── Calcular rango del mes ANTERIOR ──────────────────────────────────────
  const now = new Date()
  let mesAnteriorNum = now.getMonth() - 1  // 0-indexed
  let yearAnterior = now.getFullYear()
  if (mesAnteriorNum < 0) {
    mesAnteriorNum = 11  // Diciembre
    yearAnterior = yearAnterior - 1
  }

  const inicioMesAnterior = new Date(yearAnterior, mesAnteriorNum, 1).toISOString()
  const finMesAnterior = new Date(yearAnterior, mesAnteriorNum + 1, 0, 23, 59, 59).toISOString()
  const nombreMesAnterior = `${MESES_ES[mesAnteriorNum]} ${yearAnterior}`

  // ── Calcular rango del mes ANTERIOR-ANTERIOR (para comparación) ───────────
  let mesDosAtrasNum = mesAnteriorNum - 1
  let yearDosAtras = yearAnterior
  if (mesDosAtrasNum < 0) {
    mesDosAtrasNum = 11
    yearDosAtras = yearDosAtras - 1
  }

  const inicioMesDosAtras = new Date(yearDosAtras, mesDosAtrasNum, 1).toISOString()
  const finMesDosAtras = new Date(yearDosAtras, mesDosAtrasNum + 1, 0, 23, 59, 59).toISOString()

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
    console.error('reporte-mensual-estudios: error obteniendo estudios:', estudiosErr?.message)
    return json({ error: 'Error obteniendo estudios', detail: estudiosErr?.message }, 500)
  }

  // ── Obtener reservas del mes anterior ─────────────────────────────────────
  // OJO: la tabla `reservas` NO tiene columna estudio_id. El estudio se obtiene
  // vía clase: reservas.clase_id -> clases.estudio_id (ver claseEstudioMap).
  const { data: reservasMesAnterior, error: reservasErr } = await adminSupabase
    .from('reservas')
    .select('creditos_usados, estado, clase_id, usuario_id, created_at')
    .gte('created_at', inicioMesAnterior)
    .lte('created_at', finMesAnterior)

  // ── Obtener reservas del mes dos atrás (para comparación) ─────────────────
  const { data: reservasMesDosAtras, error: reservas2Err } = await adminSupabase
    .from('reservas')
    .select('clase_id')
    // Incluye 'ausente' y 'completada': son reservas que el estudio cobra.
    // Sin 'completada' el reporte del mes pasado saldria casi vacio, porque
    // el cron completar-reservas ya las movio a ese estado.
    .in('estado', ['confirmada', 'presente', 'ausente', 'completada'])
    .gte('created_at', inicioMesDosAtras)
    .lte('created_at', finMesDosAtras)

  // ── Obtener clases del mes anterior (para hora pico) ──────────────────────
  const { data: clasesDelMes, error: clasesErr } = await adminSupabase
    .from('clases')
    .select('id, nombre, estudio_id, fecha, tipo')
    .gte('fecha', inicioMesAnterior)
    .lte('fecha', finMesAnterior)

  // Valor global del crédito (fallback si el estudio no tiene el suyo).
  const { data: cfgVal, error: cfgErr } = await adminSupabase
    .from('configuracion_global')
    .select('valor')
    .eq('clave', 'valor_credito_ars')
    .maybeSingle()
  // Fail-LOUD: si alguna consulta rompio, cortamos con 500 en vez de seguir con
  // listas vacias y terminar en un 200 que no manda nada. Ese fallo silencioso
  // es lo que tuvo a aviso-cobro-manana sin mandar avisos sin que se notara.
  const fallas = [
    ['reservas_mes_anterior', reservasErr],
    ['reservas_mes_dos_atras', reservas2Err],
    ['clases_del_mes', clasesErr],
    ['configuracion_global', cfgErr],
  ].filter(([, e]) => e) as Array<[string, { message: string }]>
  if (fallas.length) {
    const detalle = fallas.map(([q, e]) => `${q}: ${e.message}`).join(' | ')
    console.error('reporte-mensual-estudios: consultas fallidas →', detalle)
    return json({ error: 'Error obteniendo datos del reporte', detail: detalle }, 500)
  }

  const valorGlobal = parseInt(String(cfgVal?.valor ?? '1000'), 10) || 1000

  const claseMap: Record<number, { nombre: string; estudio_id: number; hora: number; tipo: string }> = {}
  for (const c of (clasesDelMes ?? [])) {
    const dt = new Date(c.fecha as string)
    claseMap[c.id as number] = {
      nombre: c.nombre as string,
      estudio_id: c.estudio_id as number,
      hora: dt.getHours(),
      tipo: (c.tipo as string) ?? 'clase',
    }
  }

  // ── Reservas históricas de los usuarios del mes (para "alumnos nuevos") ────
  // reservas.estudio_id no existe: mapeamos cada reserva a su estudio vía clase.
  const usuariosMesAnterior = Array.from(
    new Set((reservasMesAnterior ?? []).map((r) => r.usuario_id as string)),
  )
  const { data: reservasAntiguas } = usuariosMesAnterior.length > 0
    ? await adminSupabase
        .from('reservas')
        .select('usuario_id, clase_id')
        .in('usuario_id', usuariosMesAnterior)
        .lt('created_at', inicioMesAnterior)
        .limit(10000)
    : { data: [] as Array<{ usuario_id: string; clase_id: number }> }

  // ── Mapa clase_id -> {estudio_id, tipo} para TODAS las clases referenciadas
  // por reservas (mes anterior, dos atrás e históricas). Es la fuente de verdad
  // para mapear reserva -> estudio, ya que reservas no tiene estudio_id.
  const claseIdsReferenciadas = Array.from(
    new Set(
      [
        ...(reservasMesAnterior ?? []).map((r) => r.clase_id as number),
        ...(reservasMesDosAtras ?? []).map((r) => r.clase_id as number),
        ...((reservasAntiguas ?? []) as Array<{ clase_id: number }>).map(
          (r) => r.clase_id as number,
        ),
      ].filter((id) => id != null),
    ),
  )
  const claseEstudioMap: Record<number, { estudio_id: number; tipo: string }> = {}
  // Reusar lo que ya tenemos en claseMap (clases del mes)
  for (const [idStr, info] of Object.entries(claseMap)) {
    claseEstudioMap[parseInt(idStr)] = {
      estudio_id: info.estudio_id,
      tipo: info.tipo,
    }
  }
  const idsFaltantes = claseIdsReferenciadas.filter(
    (id) => claseEstudioMap[id] === undefined,
  )
  if (idsFaltantes.length > 0) {
    const { data: clasesExtra } = await adminSupabase
      .from('clases')
      .select('id, estudio_id, tipo')
      .in('id', idsFaltantes)
    for (const c of (clasesExtra ?? [])) {
      claseEstudioMap[c.id as number] = {
        estudio_id: c.estudio_id as number,
        tipo: (c.tipo as string) ?? 'clase',
      }
    }
  }

  // Reservas dos atrás por estudio (mapeadas vía clase)
  const reservasDosAtrasPorEstudio: Record<number, number> = {}
  for (const r of (reservasMesDosAtras ?? [])) {
    const esId = claseEstudioMap[r.clase_id as number]?.estudio_id
    if (!esId) continue
    reservasDosAtrasPorEstudio[esId] = (reservasDosAtrasPorEstudio[esId] ?? 0) + 1
  }

  // Set de "usuario|estudio" que YA eran alumnos del estudio antes del mes.
  const alumnosPreviosPorEstudio = new Set<string>()
  for (const r of ((reservasAntiguas ?? []) as Array<{ usuario_id: string; clase_id: number }>)) {
    const esId = claseEstudioMap[r.clase_id as number]?.estudio_id
    if (!esId) continue
    alumnosPreviosPorEstudio.add(`${r.usuario_id}|${esId}`)
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

  // ── Procesar estadísticas por estudio ─────────────────────────────────────
  const resultados: Array<{
    estudio: string
    enviado: boolean
    motivo?: string
  }> = []

  for (const estudio of estudios) {
    const esId = estudio.id as number
    const reservasEstudio = (reservasMesAnterior ?? []).filter(
      (r) => claseEstudioMap[r.clase_id as number]?.estudio_id === esId,
    )

    // Reservas completadas (presente)
    const reservasPresente = reservasEstudio.filter((r) => r.estado === 'presente')
    const totalReservas = reservasPresente.length

    if (totalReservas === 0) {
      resultados.push({ estudio: estudio.nombre as string, enviado: false, motivo: 'sin_reservas' })
      continue
    }

    const adminEmail = emailPorEstudio[esId]
    if (!adminEmail) {
      resultados.push({ estudio: estudio.nombre as string, enviado: false, motivo: 'sin_email_admin' })
      continue
    }

    // Alumnos nuevos: usuarios cuya primera reserva en este estudio fue este
    // mes (no tenían reservas en el estudio antes). Se resuelve con el set
    // precalculado alumnosPreviosPorEstudio (mapeado vía clase).
    const usuariosEsteMes = new Set(reservasEstudio.map((r) => r.usuario_id as string))
    const alumnosNuevos = Array.from(usuariosEsteMes).filter(
      (uid) => !alumnosPreviosPorEstudio.has(`${uid}|${esId}`),
    ).length

    // Monto neto con la MISMA fórmula que las pantallas de plata
    // (netoReserva): valor_credito del estudio, comisión por tipo y
    // fecha_inicio_cobro. Antes hardcodeaba 1000 y 15%.
    const reservasCobradas = reservasEstudio.filter((r) =>
      ['confirmada', 'presente', 'ausente', 'completada'].includes(r.estado as string)
    )
    const vCred = valorCred(estudio, valorGlobal)
    let montoBruto = 0
    let montoNeto = 0
    for (const r of reservasCobradas) {
      const cred = (r.creditos_usados as number) ?? 0
      const esWorkshop =
        claseEstudioMap[r.clase_id as number]?.tipo === 'workshop'
      montoBruto += cred * vCred
      montoNeto += netoReserva(
        { estado: r.estado as string, creditos_usados: cred, esWorkshop },
        estudio,
        valorGlobal,
      )
    }
    // % efectivo, derivado de la resta (promedio ponderado clases/workshops).
    const comisionPct = montoBruto > 0
      ? Math.round(((montoBruto - montoNeto) / montoBruto) * 100)
      : 0

    // Clase más popular
    const reservasPorClase: Record<number, number> = {}
    for (const r of reservasEstudio) {
      const claseId = r.clase_id as number
      if (!claseId) continue
      reservasPorClase[claseId] = (reservasPorClase[claseId] ?? 0) + 1
    }
    let clasePopularNombre = 'Sin datos'
    if (Object.keys(reservasPorClase).length > 0) {
      const topClaseId = parseInt(
        Object.entries(reservasPorClase).reduce((a, b) => a[1] >= b[1] ? a : b)[0]
      )
      clasePopularNombre = claseMap[topClaseId]?.nombre ?? 'Sin datos'
    }

    // Horario pico
    const horasPorFrecuencia: Record<number, number> = {}
    for (const r of reservasEstudio) {
      const claseId = r.clase_id as number
      const hora = claseMap[claseId]?.hora
      if (hora !== undefined) {
        horasPorFrecuencia[hora] = (horasPorFrecuencia[hora] ?? 0) + 1
      }
    }
    let horarioPico = 'Sin datos'
    if (Object.keys(horasPorFrecuencia).length > 0) {
      const topHora = parseInt(
        Object.entries(horasPorFrecuencia).reduce((a, b) => a[1] >= b[1] ? a : b)[0]
      )
      horarioPico = `${topHora.toString().padStart(2, '0')}:00`
    }

    // Comparación vs mes anterior-anterior
    const reservasMesAnteriorAnterior = reservasDosAtrasPorEstudio[esId] ?? 0
    let cambioPct = 0
    let cambioStr = '0%'
    if (reservasMesAnteriorAnterior > 0) {
      cambioPct = Math.round(((totalReservas - reservasMesAnteriorAnterior) / reservasMesAnteriorAnterior) * 100)
      cambioStr = cambioPct > 0 ? `+${cambioPct}%` : `${cambioPct}%`
    } else if (totalReservas > 0) {
      cambioPct = 100
      cambioStr = '+100%'
    }

    const html = buildEmailHtml({
      nombreEstudio: estudio.nombre as string,
      totalReservas,
      alumnosNuevos,
      montoNeto,
      clasePopularNombre,
      horarioPico,
      cambioStr,
      cambioPct,
      nombreMes: nombreMesAnterior,
    })

    // Modo prueba: el reporte ya esta armado, pero no se manda.
    if (dryRun) {
      resultados.push({
        estudio: estudio.nombre as string,
        enviado: false,
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
          subject: `Tu reporte mensual de ${nombreMesAnterior} 📊`,
          html,
        }),
      })

      if (resendRes.ok) {
        resultados.push({ estudio: estudio.nombre as string, enviado: true })
      } else {
        const errText = await resendRes.text()
        console.error(`reporte-mensual-estudios: error Resend para ${estudio.nombre}:`, errText)
        resultados.push({ estudio: estudio.nombre as string, enviado: false, motivo: errText })
      }
    } catch (e) {
      console.error(`reporte-mensual-estudios: excepción para ${estudio.nombre}:`, e)
      resultados.push({ estudio: estudio.nombre as string, enviado: false, motivo: String(e) })
    }
  }

  const enviados = resultados.filter((r) => r.enviado).length
  const omitidos = resultados.filter((r) => !r.enviado && r.motivo === 'sin_reservas').length
  const simulados = resultados.filter((r) => (r.motivo ?? '').startsWith('dry_run')).length
  const errores = resultados.filter((r) =>
    !r.enviado && r.motivo !== 'sin_reservas' && !(r.motivo ?? '').startsWith('dry_run')
  ).length

  console.log(`reporte-mensual-estudios${dryRun ? ' [DRY RUN]' : ''}: ${enviados} enviados, ${simulados} simulados, ${omitidos} sin reservas, ${errores} errores`)
  return json({ ok: true, dry_run: dryRun, enviados, simulados, omitidos, errores, detalle: resultados })
})

// ── Builder de HTML ───────────────────────────────────────────────────────────

function buildEmailHtml(params: {
  nombreEstudio: string
  totalReservas: number
  alumnosNuevos: number
  montoNeto: number
  clasePopularNombre: string
  horarioPico: string
  cambioStr: string
  cambioPct: number
  nombreMes: string
}): string {
  const {
    nombreEstudio,
    totalReservas,
    alumnosNuevos,
    montoNeto,
    clasePopularNombre,
    horarioPico,
    cambioStr,
    cambioPct,
    nombreMes,
  } = params

  const fmt = (n: number) => `$${n.toLocaleString('es-AR')}`
  const panelUrl = 'https://somosaura.app/estudio/cobros'

  const mensajeCrecimiento = cambioPct >= 0
    ? '¡Seguís creciendo! 🚀'
    : 'Cargá más clases para atraer más usuarios este mes.'

  return `<!DOCTYPE html>
<html lang="es">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#F7F5F2;font-family:Arial,sans-serif;">
  <div style="max-width:520px;margin:32px auto;background:#F7F5F2;padding:32px 24px;border-radius:16px;">

    <div style="text-align:center;margin-bottom:28px;">
      <div style="font-size:36px;line-height:1;">📊</div>
      <div style="font-size:22px;font-weight:700;color:#1A1A1A;margin-top:8px;">Aura</div>
    </div>

    <p style="color:#1A1A1A;font-size:16px;margin:0 0 8px;">Hola <strong>${nombreEstudio}</strong>,</p>
    <p style="color:#5F5953;font-size:15px;line-height:1.6;margin:0 0 28px;">
      Acá está tu reporte de actividad de <strong>${nombreMes}</strong>.
    </p>

    <div style="background:#1A1A1A;border-radius:16px;padding:24px;margin-bottom:24px;">
      <div style="color:#9A928B;font-size:11px;font-weight:700;letter-spacing:1px;margin-bottom:16px;text-transform:uppercase;">Resumen del mes</div>

      <div style="color:#F7F5F2;font-size:15px;margin-bottom:10px;">
        ✅ <strong>${totalReservas}</strong> reserva${totalReservas !== 1 ? 's' : ''} completada${totalReservas !== 1 ? 's' : ''}
      </div>
      <div style="color:#F7F5F2;font-size:15px;margin-bottom:10px;">
        👤 <strong>${alumnosNuevos}</strong> alumno${alumnosNuevos !== 1 ? 's' : ''} nuevo${alumnosNuevos !== 1 ? 's' : ''}
      </div>
      <div style="color:#F7F5F2;font-size:15px;margin-bottom:10px;">
        💰 <strong>${fmt(montoNeto)}</strong> cobrados
      </div>
      <div style="color:#F7F5F2;font-size:15px;margin-bottom:10px;">
        ⭐ Clase más popular: <strong>${clasePopularNombre}</strong>
      </div>
      <div style="color:#F7F5F2;font-size:15px;margin-bottom:10px;">
        🕐 Horario pico: <strong>${horarioPico} hs</strong>
      </div>

      <div style="border-top:1px solid #2A2A2A;padding-top:14px;margin-top:14px;">
        <div style="color:${cambioPct >= 0 ? '#35C759' : '#E53935'};font-size:16px;font-weight:700;margin-bottom:8px;">
          📈 ${cambioStr} vs el mes anterior
        </div>
        <div style="color:#9A928B;font-size:14px;">
          ${mensajeCrecimiento}
        </div>
      </div>
    </div>

    <div style="text-align:center;margin-bottom:28px;">
      <a href="${panelUrl}" style="display:inline-block;background:#E8763A;color:white;text-decoration:none;padding:14px 32px;border-radius:12px;font-weight:700;font-size:15px;">
        Ver panel de cobros →
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
