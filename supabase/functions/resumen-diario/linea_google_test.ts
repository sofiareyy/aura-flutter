// Correr con: node supabase/functions/resumen-diario/linea_google_test.ts

import assert from 'node:assert'
import { lineaGoogle } from './linea_google.ts'

const ROJO = '#C4562A'

// Normal: sin rojo.
for (const [dias, texto] of [[0, 'hoy'], [1, 'hace 1 día'], [3, 'hace 3 días'], [7, 'hace 7 días']] as const) {
  const l = lineaGoogle(dias)
  assert.equal(l.alerta, false, `día ${dias}`)
  assert.ok(l.html.includes(`Último ingreso con Google: <b>${texto}</b>`), l.html)
  assert.ok(!l.html.includes(ROJO))
}

// Más de 7: en rojo.
for (const dias of [8, 30, 200]) {
  const l = lineaGoogle(dias)
  assert.equal(l.alerta, true)
  assert.ok(l.html.includes(ROJO))
  assert.ok(l.html.includes(`hace ${dias} días`))
}

// Sin dato: también en rojo (mejor una falsa alarma que silencio).
for (const v of [null, undefined, NaN, -1]) {
  const l = lineaGoogle(v as number)
  assert.equal(l.alerta, true)
  assert.ok(l.html.includes(ROJO))
}

console.log('linea_google_test: OK')
