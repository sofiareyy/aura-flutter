-- AURA - Métricas del dashboard del estudio (2026-07-11).
--
-- FIX 4: vistas del perfil del estudio + favoritos, expuestas al panel del
-- estudio via RPC (el estudio no puede leer favoritos_estudios de otros por RLS).

-- 1. Tabla de vistas del perfil -------------------------------------------
create table if not exists public.estudio_vistas (
  id         bigint generated always as identity primary key,
  estudio_id int  not null references public.estudios(id) on delete cascade,
  usuario_id uuid references public.usuarios(id) on delete set null,
  fecha      timestamptz not null default now()
);

create index if not exists estudio_vistas_estudio_fecha_idx
  on public.estudio_vistas (estudio_id, fecha);

alter table public.estudio_vistas enable row level security;

-- Cualquiera autenticado puede registrar una vista (al abrir el perfil).
drop policy if exists estudio_vistas_insert on public.estudio_vistas;
create policy estudio_vistas_insert
  on public.estudio_vistas
  for insert
  to authenticated
  with check (true);

-- Las lecturas se hacen solo via la RPC (security definer), no por policy.

-- 2. RPC de métricas: favoritos + vistas del mes --------------------------
-- Autorizado para el admin/dueño del estudio o un superadmin.
create or replace function public.estudio_metricas(p_estudio_id int)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid        uuid := auth.uid();
  v_ok         boolean;
  v_favoritos  int;
  v_vistas_mes int;
  v_inicio_mes timestamptz;
begin
  if v_uid is null then
    return json_build_object('ok', false, 'error', 'no_auth');
  end if;

  select
    exists (select 1 from public.admin_users where user_id = v_uid)
    or exists (
      select 1 from public.estudio_admins
       where estudio_id = p_estudio_id and usuario_id = v_uid
    )
  into v_ok;

  if not v_ok then
    return json_build_object('ok', false, 'error', 'forbidden');
  end if;

  select count(*) into v_favoritos
    from public.favoritos_estudios
   where estudio_id = p_estudio_id;

  v_inicio_mes := date_trunc(
    'month', timezone('America/Argentina/Buenos_Aires', now())
  );
  select count(*) into v_vistas_mes
    from public.estudio_vistas
   where estudio_id = p_estudio_id
     and fecha >= v_inicio_mes;

  return json_build_object(
    'ok', true,
    'favoritos', coalesce(v_favoritos, 0),
    'vistas_mes', coalesce(v_vistas_mes, 0)
  );
end;
$$;

grant execute on function public.estudio_metricas(int) to authenticated;
