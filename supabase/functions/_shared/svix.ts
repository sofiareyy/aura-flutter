// Verificación de la firma de los webhooks de Resend (los manda Svix).
//
// Lo firmado es `${svix-id}.${svix-timestamp}.${cuerpo}` con HMAC-SHA256, y la
// clave es el secreto `whsec_...` decodificado de base64 (sin el prefijo).
// El header `svix-signature` trae una o más firmas: "v1,<b64> v1,<b64>".
// Se rechaza un timestamp de más de 5 minutos para que no se pueda reenviar
// un aviso viejo.

const TOLERANCIA_S = 5 * 60

function b64ABytes(b64: string): Uint8Array {
  const bin = atob(b64)
  const out = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i)
  return out
}

function bytesAB64(bytes: Uint8Array): string {
  let bin = ''
  for (const b of bytes) bin += String.fromCharCode(b)
  return btoa(bin)
}

function igualesSinApuro(a: string, b: string): boolean {
  if (a.length !== b.length) return false
  let d = 0
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return d === 0
}

export async function firmarSvix(secreto: string, id: string, timestamp: string, cuerpo: string): Promise<string> {
  const clave = b64ABytes(secreto.startsWith('whsec_') ? secreto.slice(6) : secreto)
  const key = await crypto.subtle.importKey('raw', clave, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${id}.${timestamp}.${cuerpo}`))
  return bytesAB64(new Uint8Array(sig))
}

export async function verificarFirmaSvix(p: {
  secreto: string; id: string; timestamp: string; firmas: string; cuerpo: string; ahoraS?: number
}): Promise<boolean> {
  if (!p.secreto || !p.id || !p.timestamp || !p.firmas) return false
  const ts = Number(p.timestamp)
  const ahora = p.ahoraS ?? Math.floor(Date.now() / 1000)
  if (!Number.isFinite(ts) || Math.abs(ahora - ts) > TOLERANCIA_S) return false
  let esperada: string
  try {
    esperada = await firmarSvix(p.secreto, p.id, p.timestamp, p.cuerpo)
  } catch (_) {
    return false
  }
  return p.firmas.split(' ').some((f) => {
    const [version, firma] = f.split(',')
    return version === 'v1' && !!firma && igualesSinApuro(firma, esperada)
  })
}
