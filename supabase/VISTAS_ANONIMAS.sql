-- Las visitas a la ficha de un estudio se cuentan también sin cuenta.
-- APLICADO EN PRODUCCIÓN el 2026-10-10. Copia de lo que se corrió.
--
-- El problema, medido: `estudio_vistas` sólo tenía policy de INSERT para
-- `authenticated`, con `usuario_id = auth.uid()`. Una visitante sin cuenta
-- recibía 401 y la visita no se registraba. La pantalla no se rompe —el
-- insert es fire-and-forget con catch— pero el número que ve el estudio
-- estaba corto: de 337 visitas registradas, sólo 5 eran de gente sin cuenta,
-- y justamente las que llegan por un link compartido son las que faltaban.
--
-- No hace falta tocar la app: `detalle_estudio_screen` ya manda
-- `usuario_id: client.auth.currentUser?.id`, que para una invitada es null.
-- Y `estudio_metricas` cuenta las filas sin mirar el usuario, así que las
-- anónimas entran en el número del dashboard solas.

-- Deduplicación de la visita anónima.
--
-- La visita CON cuenta se deduplica por persona (`vista_reciente`, 1 hora).
-- La anónima no tiene a quién mirar: se acota por estudio. 15 segundos mata
-- el doble registro de una misma pantalla que se vuelve a montar, sin perder
-- dos visitantes distintos — con el tráfico de hoy, dos personas entrando al
-- mismo estudio en 15 segundos no pasa. Si el tráfico crece, bajar el número.
create or replace function public.vista_anonima_reciente(
  p_estudio_id integer,
  p_segundos integer default 15
)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select exists (
    select 1 from public.estudio_vistas v
     where v.usuario_id is null
       and v.estudio_id = p_estudio_id
       and v.fecha > now() - make_interval(secs => p_segundos)
  );
$$;

-- `usuario_id is null` NO es decorativo: sin eso, cualquiera con la anon key
-- (que es pública) podría cargar visitas a nombre de otra persona.
create policy estudio_vistas_insert_anon on public.estudio_vistas
  for insert to anon
  with check (
    usuario_id is null
    and not public.vista_anonima_reciente(estudio_id)
  );

-- Probado de punta a punta con la anon key, como lo hace el navegador:
--   visita anónima .......................... 201
--   la misma 2 segundos después ............. 401 (frenada)
--   otro estudio al toque ................... 201
--   visita a nombre de otra persona ......... 401 (frenada)
-- Y en el sitio publicado: la ficha de estudio pasó de 401 a 201.
