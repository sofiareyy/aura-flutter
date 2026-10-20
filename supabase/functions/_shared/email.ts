// Cosas comunes a todos los mails que manda Aura por Resend.
//
// Existe para que los mails no caigan en spam (20/10/2026, un estudio no
// encontraba el aviso de reserva):
// - Un mail sólo-HTML es una señal clásica de spam. `htmlATexto` arma la
//   versión en texto plano a partir del mismo HTML, así nunca se desincronizan.
// - El reply-to vive en un solo lugar. Lo ideal sería hola@somosaurapass.com
//   (mismo dominio que el remitente), pero el 20/10/2026 un mail de prueba a
//   hola@ NO llegó a la casilla de Aura: ImprovMX no lo está reenviando. Hasta
//   que eso ande, las respuestas van al Gmail para no perderlas.

export const REPLY_TO = 'aura.hola.app@gmail.com'

const ENTIDADES: Record<string, string> = {
  amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ',
  middot: '·', mdash: '—', ndash: '–', hellip: '…', bull: '•',
  aacute: 'á', eacute: 'é', iacute: 'í', oacute: 'ó', uacute: 'ú',
  Aacute: 'Á', Eacute: 'É', Iacute: 'Í', Oacute: 'Ó', Uacute: 'Ú',
  ntilde: 'ñ', Ntilde: 'Ñ', uuml: 'ü', iexcl: '¡', iquest: '¿',
}

function decodificar(s: string): string {
  return s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (m, e: string) => {
    if (e[0] === '#') {
      const n = e[1] === 'x' || e[1] === 'X' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10)
      return Number.isFinite(n) ? String.fromCodePoint(n) : m
    }
    return ENTIDADES[e] ?? m
  })
}

/** Versión en texto plano de un mail HTML, para el campo `text` de Resend. */
export function htmlATexto(html: string): string {
  let s = html
    // Lo que no se ve en el mail.
    .replace(/<(head|style|script|title)\b[^>]*>[\s\S]*?<\/\1>/gi, '')
    .replace(/<!--[\s\S]*?-->/g, '')
    // Los saltos del template no son renglones del mail; los ponen las etiquetas.
    .replace(/\s+/g, ' ')
    // Links: "texto (url)", salvo que el texto ya sea la url.
    .replace(/<a\b[^>]*?href\s*=\s*["']([^"']*)["'][^>]*>([\s\S]*?)<\/a>/gi, (_m, href: string, inner: string) => {
      const label = inner.replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim()
      const url = decodificar(href).trim()
      if (!url || url.startsWith('#')) return label
      const urlSinMailto = url.replace(/^mailto:/i, '')
      if (!label || decodificar(label) === urlSinMailto) return ` ${urlSinMailto} `
      return `${label} (${urlSinMailto})`
    })
    // Bloques que en el mail son renglones distintos.
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/(p|div|tr|h[1-6]|li|table|ul|ol)>/gi, '\n')
    .replace(/<li\b[^>]*>/gi, '\n• ')
    .replace(/<\/t[dh]>/gi, '  ')
    .replace(/<[^>]+>/g, '')
  s = decodificar(s)
  return s
    .split('\n')
    .map((l) => l.replace(/[ \t ]+/g, ' ').trim())
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim()
}
