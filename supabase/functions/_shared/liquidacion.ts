// Réplica server-side de lib/utils/liquidacion.dart. Fuente única de la
// fórmula de "cuánta plata recibe el estudio", para que el reporte mensual y
// el aviso de cobro den el mismo número que Cobros/Dashboard/Liquidaciones.

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

/** True si el estudio ya está en período de cobro. */
export function cobraComision(estudio: Estudio | null | undefined): boolean {
  const raw = estudio?.fecha_inicio_cobro
  if (!raw) return true
  const desde = new Date(raw)
  if (isNaN(desde.getTime())) return true
  return new Date() >= desde
}

/** Comisión efectiva (%) según tipo y período de cobro. */
export function comision(
  estudio: Estudio | null | undefined,
  esWorkshop: boolean,
): number {
  if (!cobraComision(estudio)) return 0
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

/** Neto que recibe el estudio por una reserva. 0 si el estado no se cobra. */
export function netoReserva(
  args: {
    estado?: string | null
    creditos_usados?: number | null
    esWorkshop: boolean
  },
  estudio: Estudio | null | undefined,
  valorGlobal: number,
): number {
  if (!ESTADOS_LIQUIDABLES.includes(String(args.estado))) return 0
  const cred = args.creditos_usados ?? 0
  if (cred <= 0) return 0
  const bruto = cred * valorCredito(estudio, valorGlobal)
  const pct = comision(estudio, args.esWorkshop)
  return Math.round(bruto * ((100 - pct) / 100))
}
