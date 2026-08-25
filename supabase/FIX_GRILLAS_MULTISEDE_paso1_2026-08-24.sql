-- ═══════════════════════════════════════════════════════════════════════════
-- FIX · dos sedes, PASO 1: la RLS de horarios_fijos mira estudio_admins
-- 2026-08-24
--
-- EL BUG
-- Las 4 policies de `horarios_fijos` autorizaban con `usuarios.estudio_id`:
--     estudio_id IN (SELECT estudio_id FROM usuarios WHERE id = auth.uid())
--
-- Pero `usuarios.estudio_id` NO es una columna de permisos: es el puntero de
-- SEDE ACTIVA (que sede esta mirando el panel). Lo confirma la base misma:
--   * `set_active_estudio()` valida el permiso en `estudio_admins` y despues
--     escribe `usuarios.estudio_id` -> es el selector de sede;
--   * `list_my_studios()` lo lee como `v_active` y lista las sedes desde
--     `estudio_admins`;
--   * `remove_estudio_admin_access()` lo re-apunta desde `estudio_admins`
--     ("si el estudio quitado era el activo, mover el activo a otro").
-- Y el selector ya existe en Dart (`mi_perfil_screen.dart`, `seleccionar_acceso_screen.dart`).
--
-- Al ser un escalar, un dueño de DOS sedes solo podia cargar grilla en la que
-- tuviera apuntada. Medido con `bottarobelen@gmail.com` (cuenta real, NO
-- superadmin, admin de las dos sedes BB segun estudio_admins):
--     grilla en Colegiales (sede activa) -> PASA
--     grilla en Urquiza  (2da sede)      -> 42501   <-- el bug
--     clase suelta en Urquiza            -> PASA    <-- `clases` ya usaba estudio_admins
--     ver sus grillas de Urquiza         -> 0 filas
-- En produccion: BB Estudio Urquiza tiene 0 grillas y 0 clases.
--
-- EL ARREGLO
-- `es_miembro_de_estudio(bigint)` (SECURITY DEFINER, ya existente), que es lo
-- que YA usan `clases`, `estudios`, `estudios_datos_cobro` y las 15 funciones
-- de acceso. Esto alinea `horarios_fijos` con `clases`: la incoherencia entre
-- las dos era exactamente el bug.
--
-- NO AMPLIA PERMISOS. Al contrario, es mas estricto: hoy alcanza con que el
-- puntero apunte ahi; ahora hay que estar en `estudio_admins`, que es una
-- tabla que el usuario NO puede escribirse (solo tiene policies de SELECT).
-- Se conserva el comportamiento actual respecto de las profes: hoy una profe
-- con el puntero seteado puede cargar grilla, y `es_miembro_de_estudio` no
-- filtra por rol, asi que sigue pudiendo. Si algun dia se quiere restringir a
-- estudio/admin_estudio, es agregar el filtro de rol aca.
--
-- El panel no mezcla sedes: el Dart filtra explicito
-- (`getHorariosFijosDeEstudio` -> `.eq('estudio_id', getCurrentStudioId())`).
-- La RLS deja de hacer de filtro visual y vuelve a ser solo guardia.
--
-- Las 4 policies pasan de `to public` a `to authenticated`: anon tiene
-- auth.uid() null, con lo cual `es_miembro_de_estudio` le da false igual, pero
-- explicitarlo evita evaluar la funcion en cada fila para un anonimo.
--
-- ⚠️ FUERA DE ALCANCE DE ESTE PASO (anotado, no tocado):
--   * `estudio_alumnos` tiene las otras 4 policies con el mismo error de
--     categoria. Hoy: 0 filas y 0 estudios en modo gestion => riesgo cero.
--   * `horarios_fijos` tiene ademas una policy "todos pueden ver horarios"
--     con USING (true) para authenticated: cualquier usuario logueado ya lee
--     las grillas de todos los estudios. No lo causa este cambio.
-- ═══════════════════════════════════════════════════════════════════════════

drop policy if exists horarios_fijos_select_own on public.horarios_fijos;
drop policy if exists horarios_fijos_insert_own on public.horarios_fijos;
drop policy if exists horarios_fijos_update_own on public.horarios_fijos;
drop policy if exists horarios_fijos_delete_own on public.horarios_fijos;

create policy horarios_fijos_select_own on public.horarios_fijos
  for select to authenticated
  using (public.es_miembro_de_estudio(estudio_id));

create policy horarios_fijos_insert_own on public.horarios_fijos
  for insert to authenticated
  with check (public.es_miembro_de_estudio(estudio_id));

create policy horarios_fijos_update_own on public.horarios_fijos
  for update to authenticated
  using (public.es_miembro_de_estudio(estudio_id))
  with check (public.es_miembro_de_estudio(estudio_id));

create policy horarios_fijos_delete_own on public.horarios_fijos
  for delete to authenticated
  using (public.es_miembro_de_estudio(estudio_id));
