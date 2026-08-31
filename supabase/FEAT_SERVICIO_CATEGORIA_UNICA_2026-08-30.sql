-- =============================================================================
-- REGLA A: un servicio de precio fijo va SOLO — categoría única (2026-08-30)
-- =============================================================================
-- El agujero que cierra (medido el 30/8 con la cuenta real de Hot Clic):
-- un estudio podía tildar su servicio caro en cualquier clase — ['Yoga','Spa']
-- — y el trigger cobraba el precio del servicio en una clase que no lo es.
-- En las dos direcciones: servicio caro = la alumna paga de más; servicio
-- barato = mueve menos plata y la comisión (%) de Aura baja. Era la única
-- palanca de precio en manos del estudio; con esto vuelve a cero.
--
-- La regla, confirmada por la usuaria el 30/8: si una clase lleva un servicio
-- de precio fijo, esa tiene que ser SU ÚNICA categoría. "Si es un sauna, la
-- categoría es Sauna sola". Los combos ya son su propia categoría (decisión
-- del 27/8) y el running club entra como categoría global "Running club" con
-- precio 0 por estudio — nunca "GRATIS" pegado a otra.
--
-- Vive en servicio_precio_fijo porque por ahí pasan TODOS los caminos:
-- clases_fija_precio (crear/editar clase), horarios_fijos_fija_precio
-- (crear/editar grilla) y admin_recalcular_precios_estudio.
-- ⚠️ Si algún día existieran clases viejas mezcladas, el recálculo las
-- rechazaría entero: hoy hay CERO (medido antes de aplicar).
--
-- El form en Dart destilda las otras categorías al tildar un servicio, así
-- que el estudio normalmente nunca ve este error; es la red para el camino
-- directo por PostgREST y para apps viejas.

create or replace function public.servicio_precio_fijo(p_estudio_id bigint, p_categorias text[])
 returns table(servicio text, creditos integer)
 language plpgsql
 stable security definer
 set search_path to 'public'
as $function$
declare
  v_matches int;
  v_lista   text;
begin
  if p_estudio_id is null or p_categorias is null or cardinality(p_categorias) = 0 then
    return;
  end if;

  select count(*),
         string_agg(esp.servicio || ' (' || esp.creditos || ' cr)', ' y ' order by esp.servicio)
    into v_matches, v_lista
    from public.estudio_servicios_precio esp
   where esp.estudio_id = p_estudio_id
     and esp.activo
     and esp.servicio = any (p_categorias);

  if v_matches >= 2 then
    raise exception 'Elegiste dos servicios con precio fijo: %. Dejá uno solo, o pedile a Aura una categoría combinada.', v_lista
      using errcode = 'P0001';
  end if;

  -- REGLA A (2026-08-30): el servicio es la única categoría de la clase.
  if v_matches = 1 and cardinality(p_categorias) > 1 then
    raise exception 'Un servicio de precio fijo va solo: % no se puede mezclar con otras categorías. Dejá esa sola, o pedile a Aura una categoría combinada.', v_lista
      using errcode = 'P0001';
  end if;

  if v_matches = 1 then
    return query
      select esp.servicio, esp.creditos
        from public.estudio_servicios_precio esp
       where esp.estudio_id = p_estudio_id
         and esp.activo
         and esp.servicio = any (p_categorias);
  end if;
end;
$function$;
