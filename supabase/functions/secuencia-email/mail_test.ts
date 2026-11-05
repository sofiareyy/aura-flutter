// Correr con: node supabase/functions/secuencia-email/mail_test.ts
import assert from 'node:assert'
import { armarMail, linkDelPaso, primerNombre } from './mail.ts'
import { htmlATexto } from '../_shared/email.ts'

const baja = 'https://somosaurapass.com/baja.html?u=x&t=y'

assert.equal(primerNombre('Lucía  Pérez'), 'Lucía')
assert.equal(primerNombre(null), '')

const m1 = armarMail(1, 'Lucía Pérez', baja)
assert.equal(m1.subject, 'Ya estás en Aura')
const t1 = htmlATexto(m1.html)
assert.match(t1, /^AURA\.\nHola Lucía,/)
assert.match(t1, /Explorar clases \(https:\/\/somosaurapass\.com\/\?.*utm_content=mail1#\/explorar\)/)
assert.match(t1, /respondeme este mail/)
assert.match(t1, /No quiero recibir más estos mails/)

const m2 = armarMail(2, '', baja)
assert.equal(m2.subject, '¿Hay alguna clase que tenés ganas de probar?')
const t2 = htmlATexto(m2.html)
assert.match(t2, /^AURA\.\nHola,\n/)
assert.match(t2, /20% de descuento en tu primera compra/)
assert.match(t2, /Ver las clases \(.*#\/comprar-creditos\)/)
assert.match(t2, /Nos vemos en Aura/)
// Fotos: 4, cada una con alt, nombre debajo y el mismo link que el botón.
assert.equal((m2.html.match(/<img /g) ?? []).length, 4)
for (const n of ['Citra Barre', 'Rock Studios', 'YOYO Yoga', 'Fit Pilates']) {
  assert.ok(m2.html.includes(`alt="${n}"`), n)
  assert.match(t2, new RegExp(`${n} \\(.*#/comprar-creditos\\)`))
}
assert.equal((m2.html.match(/href="[^"]*#\/comprar-creditos"/g) ?? []).length, 5)
// Los otros dos no llevan fotos.
assert.ok(!m1.html.includes('<img') && !armarMail(3, '', baja).html.includes('<img'))

const m3 = armarMail(3, '<b>x</b>', baja)
assert.equal(m3.subject, 'Aura sigue acá para cuando quieras')
assert.ok(!m3.html.includes('<b>x</b>'))
assert.match(htmlATexto(m3.html), /Ver clases en Aura \(.*#\/explorar\)/)

assert.ok(linkDelPaso(3).endsWith('#/explorar'))
console.log('ok')
