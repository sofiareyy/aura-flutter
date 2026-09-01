-- =============================================================================
-- El estudio puede LEER sus liquidaciones (2026-09-02)
-- =============================================================================
-- Hasta hoy la única policy de `liquidaciones` era `is_admin()`: el estudio no
-- podía ver ni sus propios pagos, y su pantalla de Cobros lo compensaba
-- inventando el estado ("si no es el mes actual, decí Pagado" — sin mirar si
-- Aura pagó) y recalculando montos con la comisión de HOY, no con la sellada.
--
-- Esta policy es SOLO SELECT y sólo de las propias: crear, editar y marcar
-- pagado sigue siendo exclusivo del backoffice (is_admin). Aditiva: ninguna
-- app vieja leía esta tabla, así que no cambia nada para nadie más.

create policy "estudio ve sus liquidaciones"
  on public.liquidaciones
  for select
  using (public.es_miembro_de_estudio(estudio_id));
