-- ═══════════════════════════════════════════════════════════════════════════
-- FIX · escalada de privilegios por el email -> control de `liquidaciones`
-- 2026-08-24
--
-- EL AGUJERO (dos piezas que solas no hacen nada, juntas sí)
--
-- 1) `usuarios_bloquear_columnas_sensibles` protegia `rol`, `estudio_id` y
--    `creditos`, pero NO `email`. La policy `usuarios_update_self` deja a
--    cualquiera escribir su propia fila, asi que el email era libre.
--
-- 2) La policy de `liquidaciones` no usaba `is_admin()`: comparaba contra un
--    email hardcodeado.
--        USING (auth.uid() IN (SELECT id FROM usuarios WHERE email = 'test@aura.com'))
--
-- Encadenadas: una alumna se ponia `email='test@aura.com'` y se volvia dueña
-- del libro de liquidaciones. Medido antes del arreglo, con `julietarey2002`
-- (alumna real, rol=usuario, is_admin=false):
--     cambiarse el email        -> PASA
--     leer liquidaciones        -> ve "estudio 3 / 2026-08 / $8400"
--     insertar una falsa        -> PASA
--     modificar las ajenas      -> 2 filas
--     borrar todas              -> 2 filas
-- Acotado: `is_admin()` seguia en false, los CBU invisibles y las RPC admin
-- rechazando. Pero es el registro de lo que Aura le debe a cada estudio.
--
-- ── (a) EMAIL AL GUARD ────────────────────────────────────────────────────
-- Se BLOQUEA del todo desde el cliente. Medido antes de decidirlo:
--   * la app no tiene pantalla de cambio de mail (`editar_perfil_screen` solo
--     guarda `nombre` y `avatar_url`);
--   * ningun `update` del Dart escribe `usuarios.email`;
--   * `usuarios.email` es una COPIA, no la identidad: el login, `canjear_regalo`
--     y la reserva gratis de modo gestion leen `auth.users.email`;
--   * en produccion los 78 usuarios estan en sync con auth.users y no hubo
--     jamas un cambio de email.
-- O sea: ningun camino legitimo hacia UPDATE de esa columna.
--
-- El guard corre solo en BEFORE UPDATE, asi que el ALTA no se toca:
--   * `handle_new_user()` (trigger de auth.users) es SECURITY DEFINER y corre
--     como postgres -> exento por la guarda de `current_user`;
--   * `ensureUsuarioCreado` (auth_service.dart:270) hace INSERT, no UPDATE.
--
-- ⚠️ PENDIENTE ANOTADO: si algun dia se hace la pantalla de cambio de mail,
-- el camino correcto es `auth.updateUser` (que verifica el mail nuevo) MAS un
-- trigger de sync sobre auth.users que copie el valor aca. Hoy nada
-- re-sincroniza la copia. Ver RETOMAR_ACA.
--
-- ── (b) LIQUIDACIONES CON is_admin() ──────────────────────────────────────
-- `is_admin()` mira `admin_users.user_id`, que es una FK contra el uuid del
-- usuario: no hay columna que la victima pueda escribirse a si misma.
--
-- El cron y el backoffice server-side NO se ven afectados: `service_role` y
-- `postgres` tienen bypassrls (medido), y `admin_delete_estudio` --la unica
-- funcion que escribe la tabla-- es SECURITY DEFINER.
-- El uso legitimo que SI pasa por la policy es la pantalla del backoffice
-- (`admin_liquidaciones_screen.dart`), que hace select/insert/update directos
-- por PostgREST como el admin logueado: por eso la policy queda FOR ALL.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── (a) ───────────────────────────────────────────────────────────────────
create or replace function public.usuarios_bloquear_columnas_sensibles()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
begin
  -- Solo frenamos la escritura DIRECTA del cliente. Los RPC security definer
  -- (owned by postgres) y el service_role corren con otro current_user y pasan.
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if new.rol is distinct from old.rol then
    raise exception 'No se puede cambiar el rol desde el cliente';
  end if;

  if new.estudio_id is distinct from old.estudio_id then
    raise exception 'No se puede cambiar el estudio desde el cliente';
  end if;

  if new.creditos is distinct from old.creditos then
    raise exception 'Los creditos se ajustan solo por el ledger';
  end if;

  -- 2026-08-24: el email es una COPIA de auth.users.email, no la identidad.
  -- Dejarlo escribible permitia hacerse pasar por otra cuenta ante cualquier
  -- chequeo que compare por email (era el caso de la policy de liquidaciones).
  -- El mail se cambia por Supabase Auth, que verifica el nuevo, no por aca.
  if new.email is distinct from old.email then
    raise exception 'El email no se cambia desde el cliente';
  end if;

  return new;
end;
$function$;

-- ── (b) ───────────────────────────────────────────────────────────────────
drop policy if exists "admin gestiona liquidaciones" on public.liquidaciones;

create policy "admin gestiona liquidaciones"
  on public.liquidaciones
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());
