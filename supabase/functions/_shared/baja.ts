// Baja de los mails que no son avisos de una reserva o un pago (regalos,
// invitaciones a volver, secuencia de bienvenida). Lo que se usa en más de
// una función vive acá para que el link del pie y el botón de Gmail apunten
// siempre a lo mismo.
//
// Cómo funciona:
// - Cada mail lleva un link personal: somosaurapass.com/baja.html?u=<id>&t=<firma>.
//   La firma es un HMAC del id con MAIL_BAJA_SECRET, así nadie puede dar de
//   baja a otra persona adivinando ids. No pide login: un toque y listo.
// - El mismo link, apuntando directo a la función `mail-baja`, va en el
//   encabezado List-Unsubscribe. Es el "Anular suscripción" que Gmail muestra
//   arriba del mail; Gmail le hace un POST (RFC 8058) y no abre ninguna página.
// - La baja se guarda en `public.mail_bajas`, por EMAIL (igual que las cuentas
//   internas): si alguien borra la cuenta y vuelve, la baja se mantiene.
//
// Los avisos de reservas, pagos y cancelaciones NO miran esta tabla.

export const WEB_BAJA = 'https://somosaurapass.com/baja.html'
export const FUNCION_BAJA = 'https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/mail-baja'

function b64url(bytes: Uint8Array): string {
  let bin = ''
  for (const b of bytes) bin += String.fromCharCode(b)
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

/** Firma corta del id de usuaria. Mismo secreto → misma firma, siempre. */
export async function firmaBaja(usuarioId: string, secreto: string): Promise<string> {
  if (!secreto) throw new Error('MAIL_BAJA_SECRET vacío')
  const enc = new TextEncoder()
  const key = await crypto.subtle.importKey(
    'raw', enc.encode(secreto), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  )
  const sig = await crypto.subtle.sign('HMAC', key, enc.encode('baja:' + usuarioId.toLowerCase()))
  return b64url(new Uint8Array(sig)).slice(0, 32)
}

/** Compara sin cortar en el primer carácter distinto. */
export async function firmaValida(usuarioId: string, firma: string, secreto: string): Promise<boolean> {
  if (!usuarioId || !firma || !secreto) return false
  const esperada = await firmaBaja(usuarioId, secreto)
  if (esperada.length !== firma.length) return false
  let dif = 0
  for (let i = 0; i < esperada.length; i++) dif |= esperada.charCodeAt(i) ^ firma.charCodeAt(i)
  return dif === 0
}

export async function linkDeBaja(usuarioId: string, secreto: string): Promise<string> {
  const t = await firmaBaja(usuarioId, secreto)
  return `${WEB_BAJA}?u=${encodeURIComponent(usuarioId)}&t=${t}`
}

/** Encabezados para el botón de baja de Gmail / Yahoo / Apple Mail. */
export async function headersDeBaja(usuarioId: string, secreto: string): Promise<Record<string, string>> {
  const t = await firmaBaja(usuarioId, secreto)
  return {
    'List-Unsubscribe': `<${FUNCION_BAJA}?u=${encodeURIComponent(usuarioId)}&t=${t}>`,
    'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click',
  }
}

/** Pie de mail con el link de baja. Va adentro de la tarjeta del mail. */
export function pieDeBaja(link: string): string {
  return `<p style="margin:28px 0 0;color:#6E6761;font-size:12px;line-height:1.5;font-family:Arial,sans-serif">
            Te escribimos porque tenés una cuenta en Aura.
            <a href="${link}" style="color:#6E6761;text-decoration:underline">No quiero recibir más estos mails</a>.
            Los avisos de tus reservas te van a seguir llegando.
          </p>`
}
