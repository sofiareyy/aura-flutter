// Elimina la cuenta del usuario logueado. Requisito de Apple App Store:
// los usuarios tienen que poder borrar su cuenta y todos sus datos desde
// dentro de la app.
//
// Flujo:
//   1) JWT auth via x-aura-auth header. Verificamos que el caller sea
//      quien dice ser.
//   2) Para reservas confirmadas / pre_confirmadas de clases futuras del
//      usuario: devolvemos los creditos usados via grant_user_credits
//      (con fallback a update directo), y borramos las filas.
//   3) Si el usuario es admin de uno o mas estudios:
//      - Para cada clase de ese estudio en el futuro: devolvemos creditos
//        a cada alumno con reserva confirmada, eliminamos las reservas y
//        eliminamos la clase. Mismo patron que cancelarClaseConDevolucion.
//      - Eliminamos los horarios_fijos del estudio.
//      - Eliminamos los registros en estudio_admins del usuario.
//      No eliminamos el estudio mismo (puede ser util mantenerlo si hay
//      otros admins o historico). Si el usuario era el unico admin queda
//      "huerfano" y un superadmin de backoffice puede limpiarlo.
//   4) Limpieza de datos transversales del usuario: lista_espera,
//      notificaciones_usuario, favoritos_estudios, etc.
//   5) ANONIMIZAR la fila de public.usuarios (ya no se borra: ver abajo).
//   6) auth.admin.deleteUser(user.id) -> borra de auth.users via el
//      service role. ESTE es el borrado real de la cuenta.
//
// ============================================================================
// 2026-08-26 — POR QUE LA FILA DE `usuarios` YA NO SE BORRA
// ============================================================================
// La liquidacion del mes se calcula EN VIVO desde `reservas`
// (admin_liquidaciones_screen.dart): hasta que el mes se liquida, lo que se le
// debe al estudio existe SOLO como filas en esa tabla. Y habia 12 FK con
// ON DELETE CASCADE colgando de `usuarios`, asi que borrar la fila se llevaba
// puestas `reservas`, `pagos` y `creditos_movimientos`.
// Medido: borrar a una alumna se llevaba una reserva `completada` de 18
// creditos ya facturados a Citra. El estudio perdia ese ingreso en silencio.
//
// El arreglo es dar vuelta el modelo: en vez de borrar la fila y pelear contra
// 12 CASCADE, se ANONIMIZA la fila (lapida) y se borra la cuenta de auth.
// - El dato personal se va de verdad: nombre, email, foto, codigo de referido,
//   datos de suscripcion.
// - La cuenta desaparece: sin `auth.users` no se puede iniciar sesion, y no
//   queda contrasena ni identidad de Google/Apple.
// - Todo lo que cuelga sigue valido sin tocar el esquema: las reservas siguen
//   contando para la liquidacion, los pagos para la contabilidad, el ledger de
//   creditos cierra, la resena figura como "Anonimo" y el log de auditoria
//   sobrevive.
//
// La fila lapida se reconoce por `rol = 'eliminado'`. Excluila de cualquier
// metrica de usuarias activas.
//
// Esto NO reemplaza pasar esas FK a ON DELETE SET NULL: eso sigue siendo la red
// de seguridad para el dia que alguien borre una fila de `usuarios` por SQL o
// desde otro camino. Pero ya no es urgente.
// ============================================================================
//
// Errores: si cualquier paso truena devolvemos el detalle para que la app
// muestre el problema. Aunque la app deberia siempre disparar de nuevo si
// hay un fallo parcial.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

// Los estados que valen plata para el estudio. Tiene que coincidir con
// AppConstants.estadosLiquidables del Dart: si cambia alla, cambia aca, o la
// liquidacion y el borrado de cuenta dejan de estar de acuerdo.
const ESTADOS_LIQUIDABLES = ['confirmada', 'presente', 'ausente', 'completada']

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const jwt = req.headers.get('x-aura-auth')?.trim() ?? ''
    if (!jwt) return json({ error: 'Sin autorizacion' }, 401)

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    // Cliente con JWT para resolver el usuario del caller.
    const userClient = createClient(supabaseUrl, anonKey)
    const { data: { user }, error: authError } =
      await userClient.auth.getUser(jwt)
    if (authError || !user) {
      return json({ error: 'No autorizado' }, 401)
    }

    const callerId = user.id

    // Cliente con service role para todo el cleanup. Bypassa RLS y nos
    // permite tocar auth.users via admin API.
    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    })

    // Body opcional: si trae target_user_id Y el caller es admin del
    // backoffice (presente en admin_users), borramos ESE usuario en
    // lugar del caller. Sino, borramos al caller.
    const body = await req.json().catch(() => null)
    const targetUserId =
      typeof body?.target_user_id === 'string' && body.target_user_id.length > 0
        ? body.target_user_id
        : null

    let uid = callerId
    if (targetUserId && targetUserId !== callerId) {
      // Verificar que el caller es admin del backoffice.
      const { data: adminRow } = await admin
        .from('admin_users')
        .select('user_id')
        .eq('user_id', callerId)
        .maybeSingle()
      if (!adminRow) {
        return json({ error: 'No autorizado' }, 403)
      }
      uid = targetUserId
    }

    let totalCreditosDevueltosAlUsuario = 0
    let totalReservasCanceladas = 0
    let totalAlumnosNotificados = 0
    let totalClasesEliminadas = 0
    let totalClasesCanceladas = 0
    let totalHorariosEliminados = 0
    const estudiosAfectados: number[] = []

    // ---------- 1) Devolver creditos al PROPIO usuario por reservas futuras ----------
    const ahoraIso = new Date().toISOString()
    const { data: misReservasFuturas } = await admin
      .from('reservas')
      .select('id, codigo_qr, creditos_usados, clase_id, clases!inner(id, nombre, fecha)')
      .eq('usuario_id', uid)
      .in('estado', ['confirmada', 'pre_confirmada'])
      .gte('clases.fecha', ahoraIso)

    for (const r of (misReservasFuturas ?? [])) {
      const creditos = Number(r.creditos_usados ?? 0)
      const claseId = Number(r.clase_id)
      // deno-lint-ignore no-explicit-any
      const claseNombre = (r as any).clases?.nombre ?? 'clase cancelada'

      if (creditos > 0) {
        const { error: grantErr } = await admin.rpc('grant_user_credits', {
          p_user_id: uid,
          p_amount: creditos,
          p_source: 'eliminacion_cuenta',
          p_description: `Devolución por cancelacion: ${claseNombre}`,
          p_expires_at: new Date(Date.now() + 60 * 86400_000).toISOString(),
        })
        if (grantErr) {
          // Fallback: update directo
          const { data: u } = await admin
            .from('usuarios')
            .select('creditos')
            .eq('id', uid)
            .maybeSingle()
          if (u) {
            await admin
              .from('usuarios')
              .update({ creditos: (u.creditos ?? 0) + creditos })
              .eq('id', uid)
          }
        }
        totalCreditosDevueltosAlUsuario += creditos
      }

      // Restaurar lugar en la clase (read + write porque PostgREST no
      // soporta expresiones tipo "col = col + 1").
      if (claseId) {
        const { data: c } = await admin
          .from('clases')
          .select('lugares_disponibles')
          .eq('id', claseId)
          .maybeSingle()
        if (c) {
          await admin.from('clases').update({
            lugares_disponibles: (c.lugares_disponibles ?? 0) + 1,
          }).eq('id', claseId)
        }
      }
      totalReservasCanceladas++
    }

    // Las reservas NO se borran: son la evidencia de lo que el estudio tiene
    // por cobrar. Las futuras que acabamos de reembolsar pasan a 'cancelada'
    // (estado no liquidable) para que el estudio no cobre algo que se devolvio;
    // las pasadas quedan intactas y siguen contando para su liquidacion.
    // La identidad se va aparte, al anonimizar la fila de `usuarios`.
    for (const r of (misReservasFuturas ?? [])) {
      const { error: cancelErr } = await admin
        .from('reservas')
        .update({ estado: 'cancelada' })
        .eq('id', Number(r.id))
      if (cancelErr) {
        console.error('delete-account: no se pudo cancelar la reserva',
          r.id, cancelErr)
      }
    }

    // Las pre_confirmadas que nunca se confirmaron no son evidencia de nada:
    // no se cobro ni se presto servicio. Esas si se borran.
    await admin
      .from('reservas')
      .delete()
      .eq('usuario_id', uid)
      .eq('estado', 'pre_confirmada')

    // ---------- 2) Si soy admin de estudios, cancelar sus clases ----------
    const { data: misEstudios } = await admin
      .from('estudio_admins')
      .select('estudio_id')
      .eq('usuario_id', uid)

    for (const row of (misEstudios ?? [])) {
      const estudioId = Number(row.estudio_id)
      if (!estudioId) continue
      estudiosAfectados.push(estudioId)

      // Clases futuras de este estudio
      const { data: clases } = await admin
        .from('clases')
        .select('id, nombre, fecha')
        .eq('estudio_id', estudioId)
        .gte('fecha', ahoraIso)

      for (const c of (clases ?? [])) {
        const claseId = Number(c.id)
        const claseNombre = c.nombre ?? 'clase'

        // Devolver creditos a cada alumno con reserva confirmada
        const { data: reservas } = await admin
          .from('reservas')
          .select('usuario_id, creditos_usados')
          .eq('clase_id', claseId)
          .in('estado', ['confirmada', 'pre_confirmada'])

        for (const r of (reservas ?? [])) {
          const otroUid = String(r.usuario_id ?? '')
          const cred = Number(r.creditos_usados ?? 0)
          if (otroUid && cred > 0) {
            const { error: gErr } = await admin.rpc('grant_user_credits', {
              p_user_id: otroUid,
              p_amount: cred,
              p_source: 'devolucion_cancelacion',
              p_description: `Estudio cerrado: ${claseNombre}`,
              p_expires_at: new Date(Date.now() + 90 * 86400_000).toISOString(),
            })
            if (gErr) {
              const { data: u2 } = await admin
                .from('usuarios')
                .select('creditos')
                .eq('id', otroUid)
                .maybeSingle()
              if (u2) {
                await admin
                  .from('usuarios')
                  .update({ creditos: (u2.creditos ?? 0) + cred })
                  .eq('id', otroUid)
              }
            }
            totalAlumnosNotificados++
          }
        }

        // Las que reembolsamos pasan a 'cancelada' (no liquidable): el
        // estudio no cobra lo que se devolvio, pero la fila queda.
        await admin
          .from('reservas')
          .update({ estado: 'cancelada' })
          .eq('clase_id', claseId)
          .in('estado', ['confirmada', 'pre_confirmada'])

        // ¿Queda algo que sea plata en esta clase? (presente / ausente /
        // completada, o una confirmada que no reembolsamos).
        // Antes acá había un `delete().eq('clase_id', claseId)` a secas: se
        // llevaba TODAS las reservas sin mirar el estado, incluidas las que
        // son evidencia de cobro. Y como borraba las reservas ANTES que la
        // clase, el candado `trg_clases_bloquear_borrado` no llegaba a
        // dispararse: lo salteaba por completo.
        const { count: liquidables } = await admin
          .from('reservas')
          .select('id', { count: 'exact', head: true })
          .eq('clase_id', claseId)
          .in('estado', ESTADOS_LIQUIDABLES)

        await admin.from('lista_espera').delete().eq('clase_id', claseId)

        if ((liquidables ?? 0) > 0) {
          // Hay plata en juego: la clase NO se borra, se cancela. Deja de ser
          // reservable y desaparece del lado de la alumna, pero el estudio
          // conserva lo que tiene por cobrar.
          await admin.from('clases')
            .update({ cancelada: true })
            .eq('id', claseId)
          totalClasesCanceladas++
        } else {
          // Sin evidencia de cobro: se borra, y las reservas canceladas que
          // queden se van con ella. Se respeta el candado en vez de saltearlo.
          await admin.from('reservas')
            .delete()
            .eq('clase_id', claseId)
            .not('estado', 'in', `(${ESTADOS_LIQUIDABLES.join(',')})`)
          const { error: delClaseErr } = await admin
            .from('clases').delete().eq('id', claseId)
          if (delClaseErr) {
            // El candado la frenó: la cancelamos y seguimos.
            console.error('delete-account: no se pudo borrar la clase',
              claseId, delClaseErr)
            await admin.from('clases')
              .update({ cancelada: true })
              .eq('id', claseId)
            totalClasesCanceladas++
          } else {
            totalClasesEliminadas++
          }
        }
      }

      // Borrar horarios fijos del estudio (sus clases futuras ya las
      // limpiamos arriba, las pasadas no tocamos).
      const { count: horariosCount } = await admin
        .from('horarios_fijos')
        .delete({ count: 'exact' })
        .eq('estudio_id', estudioId)
      totalHorariosEliminados += (horariosCount ?? 0)
    }

    // ---------- 3) Eliminar el rol estudio_admins del usuario ----------
    await admin.from('estudio_admins').delete().eq('usuario_id', uid)

    // ---------- 4) Limpieza transversal de tablas del usuario ----------
    // OJO: `creditos_movimientos` SALIO de esta lista el 26/8. Es el ledger de
    // creditos: es lo que hace que la contabilidad cierre, y borrarlo dejaba
    // la suma del ledger distinta de la realidad. Ahora sobrevive anonimizado,
    // apuntando a la fila lapida.
    const tablasUsuario = [
      'lista_espera',
      'notificaciones_usuario',
      'favoritos_estudios',
      'invitaciones_grupo',
      'referrals',
      'regalos',
    ]
    for (const t of tablasUsuario) {
      // Tratamos de borrar; si la tabla no existe o no tiene la columna
      // simplemente ignoramos el error.
      try {
        if (t === 'invitaciones_grupo') {
          await admin.from(t).delete().eq('invitador_id', uid)
        } else if (t === 'referrals') {
          // referrer_user_id o referred_user_id
          await admin.from(t).delete().or(
            `referrer_user_id.eq.${uid},referred_user_id.eq.${uid}`,
          )
        } else if (t === 'regalos') {
          // Solo por `remitente_id`: la tabla NO tiene `destinatario_id` (el
          // destinatario se guarda como `destinatario_email`). Filtrar por una
          // columna inexistente hacia fallar la query ENTERA con 42703, el
          // catch de abajo se lo tragaba, el regalo sobrevivia y el DELETE de
          // `usuarios` rebotaba contra regalos_remitente_id_fkey (que no tiene
          // ON DELETE CASCADE). Resultado: quien habia enviado una gift card
          // NO podia borrar su cuenta.
          // Las gift cards RECIBIDAS no se tocan: las pago otra persona.
          await admin.from(t).delete().eq('remitente_id', uid)
        } else {
          await admin.from(t).delete().eq('usuario_id', uid)
        }
      } catch (e) {
        // Non-critical para el flujo, pero se LOGUEA: tragarse este error en
        // silencio es exactamente lo que escondio los bugs de columna de
        // arriba durante meses.
        console.error(`delete-account: fallo la limpieza de ${t}:`, e)
      }
    }

    // ---------- 4b) Limpiar el dato personal que vive en `pagos` ----------
    // `pagos` se conserva (es plata que entro y tiene que cuadrar), pero dos
    // de sus columnas SI son dato personal y no alcanza con anonimizar al
    // titular: `gift_email` es el mail de quien recibe una gift card —otra
    // persona— y `gift_mensaje` es el texto que le escribio. Eso se borra.
    // El importe, el id de Mercado Pago y las fechas quedan.
    const { error: giftErr } = await admin
      .from('pagos')
      .update({ gift_email: null, gift_mensaje: null })
      .eq('user_id', uid)
      .not('gift_email', 'is', null)
    if (giftErr) {
      console.error('delete-account: no se pudo limpiar gift_email:', giftErr)
    }

    // ---------- 5) Anonimizar la fila de public.usuarios ----------
    // Ya NO se borra. Ver el bloque del encabezado: borrarla se llevaba por
    // CASCADE las reservas, los pagos y el ledger, o sea la evidencia de lo
    // que el estudio tiene por cobrar.
    // Lo que se va de verdad: nombre, email, foto, codigos de referido y todo
    // lo de suscripcion. Lo que queda es una fila sin identidad, marcada con
    // `rol = 'eliminado'`, a la que siguen colgadas las filas contables.
    const { error: anonErr } = await admin
      .from('usuarios')
      .update({
        nombre: 'Anónimo',
        // `email` es NOT NULL, asi que no puede quedar vacio. Se usa un valor
        // por fila (y no una constante) para que un indice unico futuro no
        // choque entre dos cuentas eliminadas.
        email: `anonimo+${uid}@cuenta-eliminada.aura`,
        avatar_url: null,
        codigo_referido: null,
        codigo_referido_usado: null,
        mp_subscription_id: null,
        subscription_status: null,
        renewal_date: null,
        plan: null,
        creditos: 0,
        creditos_vencimiento: null,
        estudio_id: null,
        estudio_asociado_id: null,
        empresa_id: null,
        es_corporativo: false,
        notifs_reservas: false,
        notifs_recordatorios: false,
        notifs_promos: false,
        notifs_reservas_profe: false,
        rol: 'eliminado',
      })
      .eq('id', uid)
    if (anonErr) {
      // Si esto falla, la cuenta de auth NO se borra: dejar auth borrado y el
      // dato personal intacto seria lo peor de los dos mundos.
      return json({
        error: 'No pudimos anonimizar los datos de la cuenta',
        detail: anonErr.message,
      }, 500)
    }

    // ---------- 6) Borrar de auth.users ----------
    const { error: delErr } =
      await admin.auth.admin.deleteUser(uid)
    if (delErr) {
      return json({
        error: 'No pudimos eliminar la cuenta de autenticacion',
        detail: delErr.message,
        cleanup: {
          totalReservasCanceladas,
          totalCreditosDevueltosAlUsuario,
          totalClasesEliminadas,
        totalClasesCanceladas,
          totalHorariosEliminados,
          totalAlumnosNotificados,
          estudiosAfectados,
        },
      }, 500)
    }

    return json({
      ok: true,
      summary: {
        totalReservasCanceladas,
        totalCreditosDevueltosAlUsuario,
        totalClasesEliminadas,
        totalClasesCanceladas,
        totalHorariosEliminados,
        totalAlumnosNotificados,
        estudiosAfectados,
      },
    })
  } catch (e) {
    console.error('delete-account exception:', e)
    return json({
      error: 'Error interno',
      detail: e instanceof Error ? e.message : String(e),
    }, 500)
  }
})

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
