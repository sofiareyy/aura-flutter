// Los textos de la secuencia de bienvenida, tal cual los escribió Sofía (3/11/2026).
// Mismo diseño que el mail del regalo: fondo oscuro, tarjeta, botón naranja.

import { pieDeBaja } from '../_shared/baja.ts'

export type Paso = 1 | 2 | 3

const WEB = 'https://somosaurapass.com'
const P = 'margin:0 0 16px;color:#B8B0A9;font-size:15px;line-height:1.6;font-family:Arial,sans-serif'
const FIRMA = 'margin:0;color:#F5F0E8;font-size:15px;line-height:1.6;font-family:Arial,sans-serif'

export function linkDelPaso(paso: Paso): string {
  // El mail 2 lleva a los packs; el 1 y el 3, a Explorar.
  const ruta = paso === 2 ? '/comprar-creditos' : '/explorar'
  return `${WEB}/?utm_source=email&utm_medium=email&utm_campaign=bienvenida&utm_content=mail${paso}#${ruta}`
}

export function primerNombre(nombre: string | null | undefined): string {
  return String(nombre ?? '').trim().split(/\s+/)[0] ?? ''
}

function esc(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
}

export function armarMail(paso: Paso, nombre: string, linkBaja: string): { subject: string; html: string } {
  const n = primerNombre(nombre)
  const saludo = n ? `Hola ${esc(n)},` : 'Hola,'
  const p = (t: string) => `<p style="${P}">${t}</p>`

  let subject: string, cuerpo: string, boton: string, cierre: string
  if (paso === 1) {
    subject = 'Ya estás en Aura'
    cuerpo = [
      p(saludo),
      p('¡Qué lindo tenerte en Aura!'),
      p('Acá podés descubrir clases de pilates, yoga, spinning, barre y mucho más, sin tener que elegir siempre el mismo estudio.'),
      p('Es simple: elegís un pack de créditos, buscás una actividad que te guste y reservás directamente desde Aura.'),
      p('Podés empezar mirando qué clases hay disponibles cerca tuyo:'),
    ].join('\n')
    boton = 'Explorar clases'
    cierre = `${p('Y si necesitás ayuda, respondeme este mail.')}
          <p style="${FIRMA}">Sofi, de Aura 🧡</p>`
  } else if (paso === 2) {
    subject = '¿Hay alguna clase que tenés ganas de probar?'
    cuerpo = [
      p(saludo),
      p('¿Hay alguna clase que hace rato tenés ganas de probar?'),
      p('En Aura encontrás pilates, yoga, spinning, barre y otras actividades en distintos estudios. Con un mismo pack de créditos podés elegir dónde entrenar y cambiar de actividad cuando quieras.'),
      p('Además, tenés un <strong style="color:#F5F0E8">20% de descuento</strong> en tu primera compra.'),
    ].join('\n')
    boton = 'Ver las clases'
    cierre = `<p style="${FIRMA}">Nos vemos en Aura 🧡</p>`
  } else {
    subject = 'Aura sigue acá para cuando quieras'
    cuerpo = [
      p(saludo),
      p('Aura sigue acá para cuando tengas ganas de probar algo distinto.'),
      p('Podés entrar, mirar las clases disponibles esta semana y elegir la que mejor combine con vos, tus horarios y tus ganas.'),
    ].join('\n')
    boton = 'Ver clases en Aura'
    cierre = `${p('Y si hay alguna actividad o zona que te gustaría encontrar, respondeme este mail. Nos sirve mucho saber qué estás buscando.')}
          <p style="${FIRMA}">Sofi, de Aura 🧡</p>`
  }

  const html = `<!doctype html>
<html lang="es"><body style="margin:0;padding:0;background:#0D0D0D">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#0D0D0D;padding:32px 16px">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;background:#1A1A1A;border-radius:20px;padding:32px">
        <tr><td>
          <p style="margin:0 0 24px;color:#E8763A;font-size:15px;font-weight:800;letter-spacing:4px">AURA.</p>
          ${cuerpo}
          <p style="margin:8px 0 24px">
            <a href="${linkDelPaso(paso as Paso)}"
               style="display:inline-block;background:#E8763A;color:#fff;text-decoration:none;
                      padding:14px 28px;border-radius:12px;font-weight:700;font-size:15px;font-family:Arial,sans-serif">
              ${boton}
            </a>
          </p>
          ${cierre}
          ${pieDeBaja(linkBaja)}
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`
  return { subject, html }
}
