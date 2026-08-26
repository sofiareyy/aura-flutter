-- Item 16 de la Tanda C: el estudio no puede ver su lista de espera.
--
-- El problema: `lista_espera` tiene una sola policy, `waitlist_own`
-- (`auth.uid()::text = usuario_id`), así que el estudio consultando la tabla
-- recibe 0 filas. La policy abierta `waitlist_count_public` se cerró bien en
-- LISTA_ESPERA_TANDA1.sql porque exponía el `usuario_id` de todas a cualquiera;
-- NO hay que reabrirla.
--
-- Esta RPC devuelve, para un estudio, cuántas personas esperan en cada una de
-- sus clases futuras. Sólo el CONTEO: ninguna identidad sale de acá. Mostrar
-- *quiénes* esperan es una decisión de producto aparte y necesitaría otra RPC.
--
-- Una sola llamada para todo el panel: hacerlo con waitlist_count(clase_id)
-- por clase serían ~30 idas y vueltas por pantalla.

create or replace function public.estudio_lista_espera_conteo(p_estudio_id bigint)
returns table (clase_id integer, esperando integer)
language sql
stable
security definer
set search_path to 'public'
as $$
  select le.clase_id, count(*)::int as esperando
    from public.lista_espera le
    join public.clases c on c.id = le.clase_id
   where c.estudio_id = p_estudio_id
     and c.fecha >= current_date
     -- El guard: sin esto, cualquiera logueado leería la lista de espera de
     -- cualquier estudio pasando otro id.
     and public.es_miembro_de_estudio(p_estudio_id)
   group by le.clase_id;
$$;

-- anon no: hay que estar logueada Y ser del estudio.
revoke execute on function public.estudio_lista_espera_conteo(bigint) from public, anon;
grant execute on function public.estudio_lista_espera_conteo(bigint) to authenticated, service_role;
