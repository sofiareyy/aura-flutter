// Tests del link de baja. Correr con:
//   node supabase/functions/_shared/baja_test.ts

import assert from 'node:assert'
import { firmaBaja, firmaValida, headersDeBaja, linkDeBaja, pieDeBaja } from './baja.ts'

const SECRETO = 'secreto-de-prueba'
const UID = '0b9d6c1e-1111-4222-8333-444455556666'

// La firma es estable y depende del id y del secreto.
const f1 = await firmaBaja(UID, SECRETO)
assert.equal(f1, await firmaBaja(UID, SECRETO))
assert.equal(f1.length, 32)
assert.notEqual(f1, await firmaBaja(UID, 'otro-secreto'))
assert.notEqual(f1, await firmaBaja(UID.replace('6666', '6667'), SECRETO))
// Mayúsculas en el id no cambian nada (un uuid es el mismo).
assert.equal(f1, await firmaBaja(UID.toUpperCase(), SECRETO))

// Validación: sólo la firma correcta, para ese id.
assert.equal(await firmaValida(UID, f1, SECRETO), true)
assert.equal(await firmaValida(UID, f1.slice(0, 31) + (f1[31] === 'a' ? 'b' : 'a'), SECRETO), false)
assert.equal(await firmaValida(UID, f1.slice(0, 20), SECRETO), false)
assert.equal(await firmaValida(UID, '', SECRETO), false)
assert.equal(await firmaValida('', f1, SECRETO), false)
assert.equal(await firmaValida(UID, f1, ''), false)

// Sin secreto no se firma: mejor que el mail falle a que salga sin baja.
await assert.rejects(() => firmaBaja(UID, ''))

// El link del pie va a la página de la web, sin caracteres raros.
const link = await linkDeBaja(UID, SECRETO)
assert.equal(link, `https://somosaurapass.com/baja.html?u=${UID}&t=${f1}`)
assert.match(f1, /^[A-Za-z0-9_-]+$/)

// El botón de Gmail apunta a la función, con One-Click (RFC 8058).
const h = await headersDeBaja(UID, SECRETO)
assert.equal(h['List-Unsubscribe'], `<https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/mail-baja?u=${UID}&t=${f1}>`)
assert.equal(h['List-Unsubscribe-Post'], 'List-Unsubscribe=One-Click')

// El pie lleva el link y aclara que los avisos de reservas siguen.
const pie = pieDeBaja(link)
assert.ok(pie.includes(`href="${link}"`))
assert.ok(pie.includes('No quiero recibir más estos mails'))
assert.ok(pie.includes('reservas te van a seguir llegando'))

console.log('baja_test: OK')
