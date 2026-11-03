// Correr con: node supabase/functions/_shared/svix_test.ts

import assert from 'node:assert'
import { createHmac } from 'node:crypto'
import { firmarSvix, verificarFirmaSvix } from './svix.ts'

const CLAVE = Buffer.from('clave-de-prueba-para-svix-1234567890').toString('base64')
const SECRETO = 'whsec_' + CLAVE
const ID = 'msg_2abc'
const TS = '1762200000'
const CUERPO = '{"type":"email.bounced","data":{"to":["x@y.com"]}}'

// La firma coincide con la que arma Svix (HMAC-SHA256 de "id.ts.cuerpo").
const esperada = createHmac('sha256', Buffer.from(CLAVE, 'base64')).update(`${ID}.${TS}.${CUERPO}`).digest('base64')
assert.equal(await firmarSvix(SECRETO, ID, TS, CUERPO), esperada)

const base = { secreto: SECRETO, id: ID, timestamp: TS, cuerpo: CUERPO, ahoraS: 1762200030 }

// Válida, también entre varias firmas.
assert.equal(await verificarFirmaSvix({ ...base, firmas: `v1,${esperada}` }), true)
assert.equal(await verificarFirmaSvix({ ...base, firmas: `v1,otraFirma= v1,${esperada}` }), true)

// Inválidas.
assert.equal(await verificarFirmaSvix({ ...base, firmas: 'v1,AAAA' }), false)
assert.equal(await verificarFirmaSvix({ ...base, firmas: `v2,${esperada}` }), false)
assert.equal(await verificarFirmaSvix({ ...base, cuerpo: CUERPO.replace('x@y', 'z@y'), firmas: `v1,${esperada}` }), false)
assert.equal(await verificarFirmaSvix({ ...base, secreto: 'whsec_' + Buffer.from('otra').toString('base64'), firmas: `v1,${esperada}` }), false)
assert.equal(await verificarFirmaSvix({ ...base, firmas: '' }), false)
assert.equal(await verificarFirmaSvix({ ...base, secreto: '', firmas: `v1,${esperada}` }), false)

// Timestamp viejo (más de 5 minutos): se rechaza aunque la firma esté bien.
assert.equal(await verificarFirmaSvix({ ...base, ahoraS: 1762200000 + 301, firmas: `v1,${esperada}` }), false)
assert.equal(await verificarFirmaSvix({ ...base, ahoraS: 1762200000 + 299, firmas: `v1,${esperada}` }), true)

console.log('svix_test: OK')
