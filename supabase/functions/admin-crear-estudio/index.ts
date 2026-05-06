// Crea un estudio + cuenta de auth (con email pre-verificado) + fila en
// usuarios, en una sola transaccion logica. Solo accesible para admins
// (verificado via tabla admin_users).
//
// Endpoint pensado para el backoffice. NUNCA exponer este flujo a usuarios
// regulares: usa service_role para crear cuentas sin verificacion de email.

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
    const userClient = createClient(
      supabaseUrl,
      Deno.env.get('SUPABASE_ANON_KEY')!,
    )
    const adminClient = createClient(
      supabaseUrl,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    // 1) Verificar que el caller existe y es admin
    const { data: { user }, error: authError } =
      await userClient.auth.getUser(jwt)
    if (authError || !user) {
      return json({ error: 'No autorizado' }, 401)
    }

    const { data: adminRow } = await adminClient
      .from('admin_users')
      .select('user_id')
      .eq('user_id', user.id)
      .maybeSingle()
    if (!adminRow) {
      return json({ error: 'Solo admins pueden crear estudios' }, 403)
    }

    // 2) Validar payload
    const body = await req.json().catch(() => null)
    const {
      estudio_nombre,
      email,
      password,
      categoria,
      direccion,
      barrio,
    } = body ?? {}

    if (!estudio_nombre || typeof estudio_nombre !== 'string' ||
        estudio_nombre.trim().length < 2) {
      return json({ error: 'Nombre de estudio requerido' }, 400)
    }
    if (!email || typeof email !== 'string' || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email.trim())) {
      return json({ error: 'Email invalido' }, 400)
    }
    if (!password || typeof password !== 'string' || password.length < 6) {
      return json({ error: 'Password debe tener al menos 6 caracteres' }, 400)
    }

    const emailLower = email.trim().toLowerCase()
    const nombreLimpio = estudio_nombre.trim()
    const categoriaLimpia = (categoria ?? '').toString().trim()
    const direccionLimpia = (direccion ?? '').toString().trim()
    const barrioLimpio = (barrio ?? '').toString().trim()

    // 3) Crear estudio primero. Si despues falla la cuenta, no queda usuario
    // colgado contra un estudio que no existe.
    const { data: estudio, error: estudioErr } = await adminClient
      .from('estudios')
      .insert({
        nombre: nombreLimpio,
        categoria: categoriaLimpia.length > 0 ? categoriaLimpia : null,
        direccion: direccionLimpia.length > 0 ? direccionLimpia : null,
        barrio: barrioLimpio.length > 0 ? barrioLimpio : null,
        activo: true,
      })
      .select('id')
      .single()

    if (estudioErr || !estudio) {
      console.error('Error creando estudio:', estudioErr?.message)
      return json(
        { error: 'No se pudo crear el estudio: ' + (estudioErr?.message ?? '') },
        500,
      )
    }
    const estudioId = estudio.id as number

    // 4) Crear auth user con email pre-confirmado
    // OJO: si el email ya esta registrado este call falla; rolleamos el estudio.
    const { data: created, error: createErr } =
      await adminClient.auth.admin.createUser({
        email: emailLower,
        password,
        email_confirm: true,
        user_metadata: {
          nombre: nombreLimpio,
          rol: 'estudio',
        },
      })

    if (createErr || !created?.user) {
      // rollback estudio
      await adminClient.from('estudios').delete().eq('id', estudioId)
      const msg = createErr?.message ?? 'unknown error'
      const friendly = msg.toLowerCase().includes('already registered') ||
                       msg.toLowerCase().includes('already exists')
        ? 'Ese email ya esta registrado en Aura.'
        : 'No se pudo crear la cuenta: ' + msg
      return json({ error: friendly }, 400)
    }

    const newUserId = created.user.id

    // 5) Insertar fila en usuarios (rol 'estudio', estudio_id seteado)
    const { error: usuarioErr } = await adminClient.from('usuarios').insert({
      id: newUserId,
      email: emailLower,
      nombre: nombreLimpio,
      rol: 'estudio',
      estudio_id: estudioId,
      creditos: 0,
    })

    if (usuarioErr) {
      // rollback ambos
      await adminClient.auth.admin.deleteUser(newUserId)
      await adminClient.from('estudios').delete().eq('id', estudioId)
      console.error('Error insertando usuario:', usuarioErr.message)
      return json(
        { error: 'No se pudo registrar el usuario en la tabla: ' + usuarioErr.message },
        500,
      )
    }

    return json({
      ok: true,
      user_id: newUserId,
      estudio_id: estudioId,
      email: emailLower,
      // El password se hace echo para que el admin lo anote y se lo de al
      // estudio. No se persiste hasheado mas alla de auth.users.
      password,
    })
  } catch (e) {
    console.error('admin-crear-estudio exception:', e)
    return json({ error: 'Error interno' }, 500)
  }
})

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
