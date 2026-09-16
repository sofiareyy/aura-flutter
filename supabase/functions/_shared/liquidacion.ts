// Réplica server-side de lib/utils/liquidacion.dart. Fuente única de la
// fórmula de "cuánta plata recibe el estudio", para que el reporte mensual y
// el aviso de cobro den el mismo número que Cobros/Dashboard/Liquidaciones.
//
// ⚠️ LA GRACIA SE EVALÚA CON LA FECHA DE LA CLASE (16/9/2026). Antes se
// comparaba `fecha_inicio_cobro` contra `new Date()`: al terminar la gracia
// la comisión se aplicaba hacia atrás (y en UTC, 3 h antes que el Dart). Una
// clase dada antes de `fecha_inicio_cobro` es del estudio al 100%.

import { diaArgentinoDe } from './mes_argentino.ts'

export const ESTADOS_LIQUIDABLES = [
  'confirmada',
  'presente',
  'ausente',
  'completada',
]

export const COMISION_CLASE_DEFAULT = 30
export const COMISION_WORKSHOP_DEFAULT = 15

type Estudio = {
  comision_aura?: number | null
  comision_workshop?: number | null
  valor_credito?: number | null
  fecha_inicio_cobro?: string | null
}

/**
 * True si a esa fecha el estudio ya está en período de cobro.
 * `fecha` es la fecha de la CLASE; se compara por día calendario argentino
 * contra `fecha_inicio_cobro` ('YYYY-MM-DD'). Sin fecha, hoy — sólo para
 * vistas previas, nunca para liquidar.
 */
export function cobraComision(
  estudio: Estudio | null | undefined,
  fecha?: Date | string | null,
): boolean {
  const raw = estudio?.fecha_inicio_cobro
  if (!raw || raw.length < 10) return true
  const inicio = raw.slice(0, 10)
  if (isNaN(new Date(inicio).getTime())) return true
  const instante = fecha == null ? new Date() : new Date(fecha)
  if (isNaN(instante.getTime())) return true
  return diaArgentinoDe(instante) >= inicio
}

/** Comisión efectiva (%) según tipo, fecha de la clase y período de cobro. */
export function comision(
  estudio: Estudio | null | undefined,
  esWorkshop: boolean,
  fecha?: Date | string | null,
): number {
  if (!cobraComision(estudio, fecha)) return 0
  if (esWorkshop) {
    return estudio?.comision_workshop ?? COMISION_WORKSHOP_DEFAULT
  }
  return estudio?.comision_aura ?? COMISION_CLASE_DEFAULT
}

/** Valor de un crédito para el estudio: el suyo, si no el global. */
export function valorCredito(
  estudio: Estudio | null | undefined,
  valorGlobal: number,
): number {
  const propio = estudio?.valor_credito
  if (propio && propio > 0) return propio
  return valorGlobal > 0 ? valorGlobal : 1000
}

/**
 * Neto que recibe el estudio por una reserva. 0 si el estado no se cobra.
 * `fecha` es la de la clase de ESTA reserva: los que llaman tienen que
 * pasarla (viene del embed de `clases`).
 */
export function netoReserva(
  args: {
    estado?: string | null
    creditos_usados?: number | null
    esWorkshop: boolean
    fecha?: Date | string | null
  },
  estudio: Estudio | null | undefined,
  valorGlobal: number,
): number {
  if (!ESTADOS_LIQUIDABLES.includes(String(args.estado))) return 0
  const cred = args.creditos_usados ?? 0
  if (cred <= 0) return 0
  const bruto = cred * valorCredito(estudio, valorGlobal)
  const pct = comision(estudio, args.esWorkshop, args.fecha)
  return Math.round(bruto * ((100 - pct) / 100))
}
