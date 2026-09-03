// Tests del corte de mes argentino. Correr con:
//   node supabase/functions/_shared/mes_argentino_test.ts
// (node 22+ ejecuta TypeScript directo; también corre con `deno test`.)
//
// ⚠️ Los valores esperados son LOS MISMOS que afirma test/mes_argentino_test.dart.
// Si cambia uno hay que cambiar el otro: son las dos mitades del mismo corte, y
// que se separen es exactamente el bug que estos tests existen para evitar.

import assert from 'node:assert'
import { limitesMesArgentino, mesArgentinoDe, mesDesplazado } from './mes_argentino.ts'

const mes = (iso: string) => mesArgentinoDe(new Date(iso))

// La franja del bug: 21:00-23:59 ART del último día del mes.
assert.equal(mes('2026-10-01T00:00:00Z'), '2026-09', '30/9 21:00 ART es septiembre')
assert.equal(mes('2026-10-01T02:59:59Z'), '2026-09', '30/9 23:59 ART es septiembre')
assert.equal(mes('2026-10-01T03:00:00Z'), '2026-10', '1/10 00:00 ART es octubre')
assert.equal(mes('2026-09-01T02:59:59Z'), '2026-08', '31/8 23:59 ART es agosto')

// Límites: inicio = día 1 00:00 ART = 03:00 UTC; fin EXCLUSIVO.
const sep = limitesMesArgentino('2026-09')
assert.equal(sep.inicioUtc, '2026-09-01T03:00:00.000Z')
assert.equal(sep.finExclusivoUtc, '2026-10-01T03:00:00.000Z')
assert.equal(limitesMesArgentino('2026-12').finExclusivoUtc, '2027-01-01T03:00:00.000Z', 'dic cruza el año')

// Sin huecos ni superposición entre meses consecutivos.
assert.equal(sep.finExclusivoUtc, limitesMesArgentino('2026-10').inicioUtc)
assert.equal(limitesMesArgentino('2026-12').finExclusivoUtc, limitesMesArgentino('2027-01').inicioUtc)

// La grieta del `lte 23:59:59`: las 23:59:59.5 no caían en NINGÚN mes.
const casi = new Date('2026-10-01T02:59:59.500Z').toISOString()
assert.ok(casi >= sep.inicioUtc && casi < sep.finExclusivoUtc, '23:59:59.5 del 30/9 cae en septiembre')

// Mes desplazado, incluido el cruce de año.
assert.equal(mesDesplazado('2026-09', -1), '2026-08')
assert.equal(mesDesplazado('2026-01', -1), '2025-12')
assert.equal(mesDesplazado('2026-01', -2), '2025-11')

console.log('mes_argentino.ts: todos los tests OK')
