// Espejo server-side de lib/utils/mes_argentino.dart. Fuente única del CORTE DE
// FACTURACIÓN, para que el reporte mensual y el aviso de cobro agrupen los
// mismos meses que la pantalla de Cobros.
//
// La regla (2/9/2026): el mes es el CALENDARIO ARGENTINO. Una reserva del 30/9
// 23:59 hora argentina es de septiembre; una del 1/10 00:01, de octubre.
// Argentina no tiene horario de verano, así que el offset fijo -3 es correcto.
//
// ⚠️ Por qué todo se construye con Date.UTC() y nunca con `new Date(y, m, 1)`:
// ese constructor usa el huso LOCAL del runtime. En Deno/Edge el huso es UTC,
// así que `new Date(2026, 8, 1)` daba 2026-09-01T00:00:00Z = 31/8 21:00 ART, y
// el rango arrancaba (y terminaba) tres horas antes de lo que debía. Con
// Date.UTC el cálculo no depende del huso de quien lo corra.

const OFFSET_ART_MS = 3 * 60 * 60 * 1000

/** 'YYYY-MM' del instante, en calendario argentino. */
export function mesArgentinoDe(instante: Date): string {
  const art = new Date(instante.getTime() - OFFSET_ART_MS)
  const y = art.getUTCFullYear()
  const m = String(art.getUTCMonth() + 1).padStart(2, '0')
  return `${y}-${m}`
}

/** El mes 'YYYY-MM' corrido `delta` meses (delta negativo = hacia atrás). */
export function mesDesplazado(mes: string, delta: number): string {
  const [y, m] = mes.split('-').map(Number)
  // Date.UTC normaliza solo: mes 0 -> diciembre del año anterior, 12 -> enero
  // del siguiente. No hace falta el if/else de "si es menor que 0".
  const d = new Date(Date.UTC(y, m - 1 + delta, 1))
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`
}

/**
 * Los límites del mes argentino como ISO UTC, para filtrar `created_at` en la
 * base: [inicio, finExclusivo). El fin EXCLUSIVO cierra la grieta del
 * `lte 23:59:59`, donde una reserva de las 23:59:59.5 no caía en ningún mes.
 *
 * Se usa con .gte(inicioUtc) y .lt(finExclusivoUtc) — NUNCA .lte().
 */
export function limitesMesArgentino(
  mes: string,
): { inicioUtc: string; finExclusivoUtc: string } {
  const [y, m] = mes.split('-').map(Number)
  // 00:00 ART = 03:00 UTC del mismo día.
  return {
    inicioUtc: new Date(Date.UTC(y, m - 1, 1) + OFFSET_ART_MS).toISOString(),
    finExclusivoUtc: new Date(Date.UTC(y, m, 1) + OFFSET_ART_MS).toISOString(),
  }
}

/** Índice 0-11 del mes, para indexar MESES_ES. */
export function mesIndice(mes: string): number {
  return Number(mes.split('-')[1]) - 1
}

/** El año del mes 'YYYY-MM'. */
export function mesAnio(mes: string): number {
  return Number(mes.split('-')[0])
}
