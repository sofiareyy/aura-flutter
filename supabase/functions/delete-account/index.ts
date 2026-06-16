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
//      notificaciones_usuario, favoritos_estudios, reservas (todas las
//      restantes), etc. La mayoria deberian tener FK con on delete
//      cascade desde public.usuarios, pero hacemos los DELETE explicitos
//      para no depender de eso.
//   5) DELETE de la fila en public.usuarios.
//   6) auth.admin.deleteUser(user.id) -> borra de auth.users via el
//      service role.
//
// Errores: si cualquier paso truena devolvemos el detalle para que la app
// muestre el problema. Aunque la app deberia siempre disparar de nuevo si
// hay un fallo parcial.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

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

    const uid = user.id

    // Cliente con service role para todo el cleanup. Bypassa RLS y nos
    // permite tocar auth.users via admin API.
    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    })

    let totalCreditosDevueltosAlUsuario = 0
    let totalReservasCanceladas = 0
    let totalAlumnosNotificados = 0
    let totalClasesEliminadas = 0
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

    // Marcar / eliminar todas mis reservas activas (no solo futuras).
    await admin
      .from('reservas')
      .delete()
      .eq('usuario_id', uid)

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

        // Borrar todas las reservas de la clase y la clase misma
        await admin.from('reservas').delete().eq('clase_id', claseId)
        await admin.from('lista_espera').delete().eq('clase_id', claseId)
        await admin.from('clases').delete().eq('id', claseId)
        totalClasesEliminadas++
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
    const tablasUsuario = [
      'lista_espera',
      'notificaciones_usuario',
      'favoritos_estudios',
      'invitaciones_grupo',
      'creditos_movimientos',
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
          await admin.from(t).delete().or(
            `remitente_id.eq.${uid},destinatario_id.eq.${uid}`,
          )
        } else {
          await admin.from(t).delete().eq('usuario_id', uid)
        }
      } catch (_) {
        // Non-critical: la app no romperia por una tabla extra
      }
    }

    // ---------- 5) Borrar fila de public.usuarios ----------
    await admin.from('usuarios').delete().eq('id', uid)

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
