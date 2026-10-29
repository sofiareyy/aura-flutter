-- 29/10/2026: el clic de Meta (fbclid) de cada persona, guardado del lado del
-- servidor para la API de Conversiones (registro, inicio de checkout y compra).
--
-- El navegador lo guarda al llegar desde un anuncio (web/aura-analytics.js,
-- cookie _fbc con el formato de Meta "fb.1.<ms del clic>.<fbclid>") y la app
-- lo manda acá apenas hay sesión (AtribucionMeta.sincronizar). Sólo web.
--
-- Se guarda cada clic distinto de la persona: el evento de compra usa el
-- último ANTERIOR a la compra. Si la cuenta se borra, sus clics se van con
-- ella (on delete cascade sobre auth.users).
--
-- Para volver atrás: ROLLBACK_atribucion_meta_2026-10-29.sql

create table if not exists public.atribucion_meta (
  id          bigserial primary key,
  usuario_id  uuid not null references auth.users (id) on delete cascade,
  fbc         text not null,
  clic_at     timestamptz not null,   -- sale del propio fbc
  guardado_at timestamptz not null default now(),
  unique (usuario_id, fbc)
);
create index if not exists atribucion_meta_usuario_clic
  on public.atribucion_meta (usuario_id, clic_at desc);

-- Sin políticas: sólo se escribe por guardar_fbc y se lee desde el servidor.
alter table public.atribucion_meta enable row level security;
revoke all on public.atribucion_meta from anon, authenticated;

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
