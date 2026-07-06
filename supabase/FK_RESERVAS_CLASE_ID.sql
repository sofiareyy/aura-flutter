-- Fix PGRST200 "could not find relationship between reservas and clases".
-- 2026-07-06.
--
-- La tabla `reservas` no tenía NINGUNA foreign key, por eso PostgREST no podía
-- resolver el embed `.from('reservas').select('..., clases(...)')` que usa la
-- pantalla de liquidaciones del backoffice.
--
-- Se crea la FK reservas.clase_id -> clases.id.
--
-- ON DELETE CASCADE (no la FK plana): hay flujos que borran una clase dejando
-- reservas que la referencian (estudio_admin_service.cancelarClase marca las
-- reservas como 'cancelada' y LUEGO borra la clase; eliminarClaseRow borra la
-- clase directo). Con RESTRICT esos DELETE fallarían. Con CASCADE, borrar una
-- clase elimina sus reservas y se evitan reservas huérfanas.
--
-- Precondición verificada: 0 reservas huérfanas (clase_id sin clase existente).

alter table public.reservas
  add constraint reservas_clase_id_fkey
  foreign key (clase_id) references public.clases(id) on delete cascade;

-- Forzar a PostgREST a recargar el schema cache para que reconozca la relación.
notify pgrst, 'reload schema';
