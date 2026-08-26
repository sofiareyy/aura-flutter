-- ═══════════════════════════════════════════════════════════════════════════
-- FIX · el estudio no veía el nombre de sus alumnas en Asistencia
-- 2026-08-25 · reportado por Citra Barre
--
-- EL BUG
-- `asistencia_screen.dart:244-255` trae la lista de asistentes y, por cada
-- reserva, hace `from('usuarios').select('nombre,email').eq('id', usuario_id)`.
-- La UNICA policy de lectura de `usuarios` era `usuarios_select_self`
-- (`auth.uid() = id`), asi que el estudio recibia `null` y la UI caia en
-- 'Alumno' / 'Sin nombre'. Medido como `citrabarre@gmail.com`: 0 filas al
-- pedir la fila de la alumna de su propia reserva.
-- Le pasaba a TODOS los estudios, con cualquier clase: no tiene nada que ver
-- con las clases huerfanas ni desalineadas.
--
-- EL ARREGLO (provisorio, hasta el build)
-- Una policy acotada: el estudio ve la fila de una usuaria SOLO si esa
-- usuaria tiene una reserva no cancelada en una clase de un estudio que el
-- administra. Va por un helper SECURITY DEFINER para no depender de la RLS
-- de `reservas`/`clases` dentro de la policy (mas simple de razonar y no
-- paga el costo de esas policies por fila).
--
-- ⚠️ LIMITACION CONOCIDA, POR ESO ES PROVISORIA
-- Una policy habilita la FILA ENTERA, no columnas sueltas. El Dart pide
-- 'nombre,email', pero alguien consultando a mano veria tambien `creditos`,
-- `plan`, `codigo_referido`, `empresa_id`, `avatar_url` de esa alumna. No
-- hay nada de plata ajena ni CBUs, y es una alumna que reservo en SU
-- estudio, pero es mas de lo que la pantalla necesita.
-- En el build entra una RPC que devuelve solo (nombre, email) y ENTONCES
-- SE DROPEA ESTA POLICY. Ver Tanda C.
--
-- No se toca `usuarios_select_self`: las policies se combinan con OR, asi
-- que cada usuaria sigue viendo su propia fila igual.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.es_alumna_de_mi_estudio(p_usuario_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  select exists (
    select 1
      from public.reservas r
      join public.clases c on c.id = r.clase_id
      join public.estudio_admins ea on ea.estudio_id = c.estudio_id
     where r.usuario_id = p_usuario_id
       and coalesce(r.estado, '') <> 'cancelada'
       and ea.usuario_id = auth.uid()
  );
$function$;

revoke execute on function public.es_alumna_de_mi_estudio(uuid) from public, anon;
grant  execute on function public.es_alumna_de_mi_estudio(uuid) to authenticated, service_role;

drop policy if exists usuarios_select_alumnas_de_mis_clases on public.usuarios;
create policy usuarios_select_alumnas_de_mis_clases on public.usuarios
  for select to authenticated
  using (public.es_alumna_de_mi_estudio(id));
