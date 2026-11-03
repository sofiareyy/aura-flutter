-- Último ingreso con Google, para el resumen diario (3/11/2026).
--
-- Google marcó como "inactivo" el único cliente OAuth del login con Google
-- (ver docs/GOOGLE_LOGIN_recrear_cliente.md). Si algún día lo borran, nadie
-- avisa: simplemente deja de entrar gente con Google. Esta función le da al
-- resumen diario cuántos días pasaron desde el último ingreso con Google.
--
-- Se mira auth.identities.updated_at y NO last_sign_in_at: este último queda
-- en la fecha de alta y no cambia con cada login (verificado el 3/11/2026).
-- Cuenta TODOS los ingresos, también los de cuentas internas: lo que importa
-- es si el cliente de Google funciona, no quién entró.
--
-- Volver atrás: drop function public.ultimo_ingreso_google();

create or replace function public.ultimo_ingreso_google()
returns jsonb
language sql stable security definer set search_path = public, auth
as $$
  select jsonb_build_object(
    'ultimo', max(i.updated_at),
    'dias', (now() at time zone 'America/Argentina/Buenos_Aires')::date
          - (max(i.updated_at) at time zone 'America/Argentina/Buenos_Aires')::date)
    from auth.identities i
   where i.provider = 'google';
$$;
revoke all on function public.ultimo_ingreso_google() from public, anon, authenticated;
grant execute on function public.ultimo_ingreso_google() to service_role;
