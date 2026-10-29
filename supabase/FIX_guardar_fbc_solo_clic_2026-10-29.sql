-- guardar_fbc vuelve a SÓLO guardar el clic de Meta (29/10/2026).
--
-- En producción, fuera del repo, se le había agregado un net.http_post que
-- mandaba CompleteRegistration a meta-capi-event cada vez que la app guardaba
-- un clic. Eso contaba como "registro" a cualquiera que entrara a su cuenta
-- desde un anuncio, aunque la cuenta tuviera meses, y dejaba afuera a quien
-- se registraba sin venir de un anuncio.
--
-- Desde ahora el registro lo manda la app (AtribucionMeta.registro, sólo web)
-- DESPUÉS de guardar el clic, y meta-capi-event lo acepta sólo si la cuenta
-- tiene menos de 7 días. Vuelta atrás: ROLLBACK_guardar_fbc_solo_clic_2026-10-29.sql

create or replace function public.guardar_fbc(p_fbc text)
 returns void
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_uid   uuid := auth.uid();
  v_clic  timestamptz;
begin
  if v_uid is null or p_fbc is null then
    return;
  end if;
  -- Mismo formato que valida aura-analytics.js. Lo que no cumple se ignora
  -- en silencio: medir nunca rompe nada.
  if length(p_fbc) > 600
     or p_fbc !~ '^fb\.1\.\d{13}\.[A-Za-z0-9_-]{10,}$' then
    return;
  end if;
  v_clic := to_timestamp(split_part(p_fbc, '.', 3)::bigint / 1000.0);
  -- Un reloj de navegador muy corrido no puede inventar un clic del futuro.
  if v_clic > now() + interval '1 day' then
    v_clic := now();
  end if;
  insert into public.atribucion_meta (usuario_id, fbc, clic_at)
  values (v_uid, p_fbc, v_clic)
  on conflict (usuario_id, fbc) do nothing;
end;
$function$;
revoke all on function public.guardar_fbc(text) from public, anon;
grant execute on function public.guardar_fbc(text) to authenticated;
