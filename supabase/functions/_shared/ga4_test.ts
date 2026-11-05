// Correr con: node supabase/functions/_shared/ga4_test.ts
import assert from 'node:assert'
import { armarCompraGa, datosGaDelPedido } from './ga4.ts'

// Fuera de la web no se guarda nada.
assert.deepEqual(datosGaDelPedido({ client_id: '1.2' }, false), { ga_client_id: null, ga_session_id: null, atribucion: null })

// Se valida todo lo que manda el navegador.
const d = datosGaDelPedido({
  client_id: '111.222', session_id: '1730000000',
  atribucion: { utm_source: ' ig ', utm_campaign: 'nov', email: 'x@y.com', fbclid: 'A'.repeat(300) },
}, true)
assert.equal(d.ga_client_id, '111.222')
assert.equal(d.ga_session_id, '1730000000')
assert.deepEqual(Object.keys(d.atribucion!).sort(), ['fbclid', 'utm_campaign', 'utm_source'])
assert.equal(d.atribucion!.utm_source, 'ig')
assert.equal(d.atribucion!.fbclid.length, 100)
assert.equal(datosGaDelPedido({ client_id: 'x@y.com', session_id: 'abc' }, true).ga_client_id, null)

const c = armarCompraGa({
  clientId: '111.222', sessionId: '1730000000', userId: 'uid', transactionId: 'pago-1',
  value: 17600, itemName: 'Pack 20', itemCategory: 'pack', atribucion: d.atribucion,
})
assert.equal(c.client_id, '111.222')
assert.equal(c.user_id, 'uid')
assert.equal(c.events[0].name, 'purchase')
assert.equal(c.events[0].params.transaction_id, 'pago-1')
assert.equal(c.events[0].params.currency, 'ARS')
assert.equal(c.events[0].params.value, 17600)
assert.equal(c.events[0].params.session_id, '1730000000')
assert.equal(c.events[0].params.utm_campaign, 'nov')
assert.ok(!JSON.stringify(c).includes('@'))
console.log('ok')
