// La línea "Último ingreso con Google" del resumen diario (3/11/2026).
//
// Google marcó como inactivo el único cliente OAuth del login con Google. Si
// lo borra, nadie avisa: la gente simplemente deja de poder entrar con Google.
// Hay unos 7 ingresos por semana, así que más de 7 días sin ninguno es la
// señal. Qué hacer: docs/GOOGLE_LOGIN_recrear_cliente.md.

export const DIAS_ALERTA = 7
const ROJO = '#C4562A'

/** `dias` = días desde el último ingreso con Google (null si nunca hubo / no se pudo leer). */
export function lineaGoogle(dias: number | null | undefined): { html: string; alerta: boolean } {
  if (dias === null || dias === undefined || !Number.isFinite(dias) || dias < 0) {
    return {
      html: `<b style="color:${ROJO}">Último ingreso con Google: no se pudo leer. Revisá que el login con Google ande.</b>`,
      alerta: true,
    }
  }
  const cuando = dias === 0 ? 'hoy' : dias === 1 ? 'hace 1 día' : `hace ${dias} días`
  if (dias > DIAS_ALERTA) {
    return {
      html: `<b style="color:${ROJO}">Último ingreso con Google: ${cuando}. Puede que el login con Google no ande.</b>`,
      alerta: true,
    }
  }
  return { html: `Último ingreso con Google: <b>${cuando}</b>`, alerta: false }
}
