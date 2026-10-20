// Tests de la versión en texto plano de los mails. Correr con:
//   node supabase/functions/_shared/email_test.ts

import assert from 'node:assert'
import { htmlATexto } from './email.ts'

// Lo invisible no aparece.
assert.equal(
  htmlATexto('<html><head><title>Aura</title><style>p{color:red}</style></head><body><p>Hola</p></body></html>'),
  'Hola',
)

// Bloques y saltos de línea se respetan; espacios del template se colapsan.
assert.equal(
  htmlATexto('<div>\n      Clase:   Pilates\n</div><div>Hora: 18:00</div><p>a<br>b</p>'),
  'Clase: Pilates\nHora: 18:00\na\nb',
)

// Links: botón con texto muestra la URL; si el texto ya es la URL, no la repite.
assert.equal(
  htmlATexto('<a href="https://somosaurapass.com/#/explorar" style="x">Buscar otra clase</a>'),
  'Buscar otra clase (https://somosaurapass.com/#/explorar)',
)
assert.equal(htmlATexto('<a href="mailto:a@b.com">a@b.com</a>'), 'a@b.com')
assert.equal(htmlATexto('<a href="https://x.com/?a=1&amp;b=2">ver</a>'), 'ver (https://x.com/?a=1&b=2)')

// Entidades.
assert.equal(htmlATexto('<p>Ma&ntilde;ana &middot; 18&nbsp;hs &#127881; &amp; m&aacute;s</p>'), 'Mañana · 18 hs 🎉 & más')

// Celdas de una tabla quedan en el mismo renglón.
assert.equal(htmlATexto('<table><tr><td>Total</td><td>$ 1.000</td></tr></table>'), 'Total $ 1.000')

// Nunca más de un renglón en blanco seguido.
assert.equal(htmlATexto('<p>a</p><p></p><p></p><p></p><p>b</p>'), 'a\n\nb')

console.log('email_test: ok')
