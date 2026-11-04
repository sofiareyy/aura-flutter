// Correr con: node supabase/functions/pago-estudio-email/mail_test.ts
import assert from 'node:assert'
import { armarMailPago, lineaSedes, nombreMes, pesos } from './mail.ts'
import { htmlATexto } from '../_shared/email.ts'

assert.equal(pesos(38400), '$38.400')
assert.equal(pesos(11000), '$11.000')
assert.equal(pesos(1234567), '$1.234.567')
assert.equal(nombreMes('2026-10'), 'octubre 2026')

const base = { estudio: 'Sitio Pilates', mes: '2026-10', monto: 11000, reservas: 1,
  numeroOperacion: '186564950751', otrasSedes: [], reenvio: false }

const m = armarMailPago(base)
assert.equal(m.subject, 'Te transferimos $11.000 de octubre 2026')
const t = htmlATexto(m.html)
assert.match(t, /Ya te transferimos lo que cobraste con Aura en octubre 2026/)
assert.match(t, /186564950751/)
assert.match(t, /1 reserva\b/)
assert.match(t, /en Cobros/)
assert.doesNotMatch(t, /sedes/)
assert.doesNotMatch(t, /reemplaza/)

// Dos sedes con la misma transferencia.
const rock = { ...base, estudio: 'Rock Studios Palermo', monto: 22400, reservas: 2,
  numeroOperacion: '186562562951', otrasSedes: [{ nombre: 'Rock Studios Recoleta', monto: 16000 }] }
assert.equal(lineaSedes(rock),
  'Esta transferencia incluye las dos sedes: Rock Studios Palermo ($22.400) y Rock Studios Recoleta ($16.000). ' +
  'En tu banco vas a ver un solo movimiento de $38.400.')

// Reenvío corregido.
const r = armarMailPago({ ...base, reenvio: true, monto: 12000 })
assert.equal(r.subject, 'Corrección: te transferimos $12.000 de octubre 2026')
assert.match(htmlATexto(r.html), /reemplaza al anterior/)

// Sin número de operación: no se inventa la línea.
const s = htmlATexto(armarMailPago({ ...base, numeroOperacion: null }).html)
assert.doesNotMatch(s, /Número de operación/)

// Nombres con caracteres raros se escapan.
assert.match(armarMailPago({ ...base, estudio: 'A&B <x>' }).html, /A&amp;B &lt;x&gt;/)

console.log('pago-estudio-email mail_test: OK')
