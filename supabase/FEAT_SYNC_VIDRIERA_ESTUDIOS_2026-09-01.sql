-- =============================================================================
-- E1 — La vidriera dice la verdad (2026-09-01)
-- =============================================================================
-- El bug: el chip de categoría de Explorar/Inicio/Mapa filtra por
-- `estudios.categorias` (lo que el estudio DECLARÓ en su perfil), no por lo
-- que realmente dicta. Yessi declara "Fitness" y tiene 70 clases de
-- "Gym / Funcional": tocar ese chip no la mostraba.
--
-- El arreglo, en BASE: sincronizar la vidriera con la realidad. Vale para
-- TODAS las apps, incluidas las ya instaladas, sin esperar un build.
--
-- Reglas de oro:
--   · SÓLO SUMA. Nunca borra lo que el estudio declaró a mano (sacar algo que
--     ya no dicta es una charla, no un cron).
--   · Agrega AL FINAL, así `categorias[1]` no cambia — es la etiqueta visible
--     de la card y la que el trigger `sync_categoria_estudio` copia al escalar.
--   · Sólo estudios activos y clases futuras no canceladas.
--   · Incluye workshops a propósito: un estudio de cerámica tiene que
--     aparecer bajo Cerámica.

create or replace function public.sync_vidriera_estudios()
 returns json
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_cambiados int := 0;
begin
  with reales as (
    select c.estudio_id, array_agg(distinct cat order by cat) as cats
      from public.clases c, unnest(c.categorias) cat
     where c.fecha > now()
       and c.cancelada = false
       and trim(coalesce(cat,'')) <> ''
     group by c.estudio_id
  ), faltantes as (
    select e.id,
           coalesce(e.categorias, '{}') ||
             coalesce(array(
               select x from unnest(r.cats) x
                where x <> all (coalesce(e.categorias, '{}'))
             ), '{}') as nuevas
      from public.estudios e
      join reales r on r.estudio_id = e.id
     where coalesce(e.activo, true)
       and exists (
         select 1 from unnest(r.cats) x
          where x <> all (coalesce(e.categorias, '{}'))
       )
  )
  update public.estudios e
     set categorias = f.nuevas
    from faltantes f
   where e.id = f.id;

  get diagnostics v_cambiados = row_count;
  return json_build_object('ok', true, 'estudios_actualizados', v_cambiados);
end;
$function$;

-- Nocturno a las 03:30: media hora después de `regenerar-grillas-diario`
-- (03:00), así las clases recién generadas ya están cuando sincroniza.
select cron.schedule(
  'sync-vidriera-estudios',
  '30 3 * * *',
  $$select public.sync_vidriera_estudios();$$
);
