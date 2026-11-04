// Texto del mail "ya te transferimos" (4/11/2026). Funciones puras, sin red,
// para poder probarlas con node y mostrarle el texto a Sofía antes de publicar.

export type OtraSede = { nombre: string; monto: number }

export type DatosMailPago = {
  estudio: string
  mes: string               // 'YYYY-MM'
  monto: number             // lo efectivamente transferido (fila + correcciones)
  reservas: number
  numeroOperacion: string | null
  otrasSedes: OtraSede[]    // otras sedes pagadas con la MISMA transferencia
  reenvio: boolean          // true = lo mandó Sofía a mano desde el backoffice
}

const MESES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio',
  'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre']

export function nombreMes(mes: string): string {
  const [a, m] = mes.split('-').map(Number)
  return MESES[(m || 1) - 1] + ' ' + a
}

export function pesos(n: number): string {
  return '$' + Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.')
}

function esc(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
}

const NUMEROS = ['', 'una', 'dos', 'tres', 'cuatro', 'cinco']

/** "Esta transferencia incluye las dos sedes: ..." o null si es una sola. */
export function lineaSedes(d: DatosMailPago): string | null {
  if (d.otrasSedes.length === 0) return null
  const todas = [{ nombre: d.estudio, monto: d.monto }, ...d.otrasSedes]
  const total = todas.reduce((a, s) => a + s.monto, 0)
  const cuantas = NUMEROS[todas.length] ?? String(todas.length)
  const detalle = todas.map((s) => `${s.nombre} (${pesos(s.monto)})`)
  const lista = detalle.slice(0, -1).join(', ') + ' y ' + detalle[detalle.length - 1]
  return `Esta transferencia incluye las ${cuantas} sedes: ${lista}. ` +
    `En tu banco vas a ver un solo movimiento de ${pesos(total)}.`
}

export const LINK_COBROS = 'https://somosaurapass.com/#/estudio/cobros'

export function armarMailPago(d: DatosMailPago): { subject: string; html: string } {
  const mes = nombreMes(d.mes)
  const subject = d.reenvio
    ? `Corrección: te transferimos ${pesos(d.monto)} de ${mes}`
    : `Te transferimos ${pesos(d.monto)} de ${mes}`

  const filas: [string, string][] = [
    ['Monto', pesos(d.monto)],
    ['Mes', `${mes} · ${d.reservas} reserva${d.reservas === 1 ? '' : 's'}`],
  ]
  if (d.numeroOperacion) filas.push(['Número de operación', d.numeroOperacion])

  const sedes = lineaSedes(d)
  const tabla = filas.map(([k, v]) =>
    `<tr><td style="padding:6px 0;color:#8F877F;font-size:14px;">${k}</td>` +
    `<td style="padding:6px 0;color:#1A1A1A;font-size:15px;font-weight:600;text-align:right;">${esc(v)}</td></tr>`,
  ).join('')

  const parrafos = [
    d.reenvio
      ? `<p style="margin:0 0 16px;color:#C4562A;font-size:14px;">Este mail reemplaza al anterior, que tenía un dato equivocado. Estos son los datos correctos.</p>`
      : '',
    `<p style="margin:0 0 16px;font-size:15px;">Hola, ${esc(d.estudio)}:</p>`,
    `<p style="margin:0 0 16px;font-size:15px;">Ya te transferimos lo que cobraste con Aura en ${mes}.</p>`,
    `<table style="width:100%;border-collapse:collapse;margin:0 0 16px;border-top:1px solid #EEE7E0;border-bottom:1px solid #EEE7E0;">${tabla}</table>`,
    sedes ? `<p style="margin:0 0 16px;font-size:14px;">${esc(sedes)}</p>` : '',
    d.numeroOperacion
      ? `<p style="margin:0 0 16px;font-size:14px;">Con el número de operación podés buscarla en tu banco.</p>`
      : '',
    `<p style="margin:0 0 20px;font-size:14px;">El detalle de cada reserva lo ves en tu panel, en Cobros.</p>`,
    `<p style="margin:0 0 24px;"><a href="${LINK_COBROS}" style="display:inline-block;background:#E8763A;color:#fff;text-decoration:none;padding:12px 20px;border-radius:10px;font-weight:600;font-size:14px;">Ver Cobros</a></p>`,
    `<p style="margin:0 0 4px;font-size:14px;">Si algo no coincide, respondé este mail.</p>`,
    `<p style="margin:0;font-size:14px;">Sofi, de Aura 🧡</p>`,
  ].filter(Boolean).join('\n')

  const html = `<!doctype html><html><head><meta charset="utf-8"><title>${esc(subject)}</title></head>` +
    `<body style="margin:0;padding:24px;background:#F7F5F2;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#1A1A1A;">` +
    `<div style="max-width:520px;margin:0 auto;background:#fff;border-radius:16px;padding:28px;">${parrafos}</div>` +
    `<p style="max-width:520px;margin:12px auto 0;color:#9A9A9A;font-size:11px;text-align:center;">Recibís este mail porque administrás este estudio en Aura.</p>` +
    `</body></html>`
  return { subject, html }
}
