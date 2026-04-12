alter table public.usuarios
  add column if not exists avatar_url text,
  add column if not exists codigo_referido text,
  add column if not exists codigo_referido_usado text,
  add column if not exists notifs_reservas boolean default true,
  add column if not exists notifs_recordatorios boolean default true,
  add column if not exists notifs_promos boolean default false;

create unique index if not exists usuarios_codigo_referido_uidx
  on public.usuarios (codigo_referido)
  where codigo_referido is not null;

create table if not exists public.favoritos_estudios (
  usuario_id uuid not null references public.usuarios(id) on delete cascade,
  estudio_id bigint not null references public.estudios(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (usuario_id, estudio_id)
);

alter table public.favoritos_estudios enable row level security;

drop policy if exists "favoritos_estudios_select_self" on public.favoritos_estudios;
create policy "favoritos_estudios_select_self"
  on public.favoritos_estudios
  for select
  using (auth.uid() = usuario_id);

drop policy if exists "favoritos_estudios_insert_self" on public.favoritos_estudios;
create policy "favoritos_estudios_insert_self"
  on public.favoritos_estudios
  for insert
  with check (auth.uid() = usuario_id);

drop policy if exists "favoritos_estudios_delete_self" on public.favoritos_estudios;
create policy "favoritos_estudios_delete_self"
  on public.favoritos_estudios
  for delete
  using (auth.uid() = usuario_id);

create or replace function public.ensure_referral_code(p_user_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_code text;
  new_code text;
begin
  select codigo_referido
    into existing_code
  from public.usuarios
  where id = p_user_id;

  if existing_code is not null and length(trim(existing_code)) > 0 then
    return upper(existing_code);
  end if;

  loop
    new_code := upper(substr(md5(random()::text || clock_timestamp()::text || p_user_id::text), 1, 8));
    exit when not exists (
      select 1 from public.usuarios where codigo_referido = new_code
    );
  end loop;

  update public.usuarios
     set codigo_referido = new_code
   where id = p_user_id;

  return new_code;
end;
$$;

create or replace function public.apply_referral_code(p_user_id uuid, p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_code text := upper(trim(p_code));
  own_code text;
  used_code text;
  referrer_id uuid;
begin
  perform public.ensure_referral_code(p_user_id);

  select codigo_referido, codigo_referido_usado
    into own_code, used_code
  from public.usuarios
  where id = p_user_id;

  if normalized_code is null or normalized_code = '' then
    return jsonb_build_object('ok', false, 'error', 'Ingresá un código válido.');
  end if;

  if used_code is not null and length(trim(used_code)) > 0 then
    return jsonb_build_object('ok', false, 'error', 'Esta cuenta ya usó un código de referido.');
  end if;

  if own_code = normalized_code then
    return jsonb_build_object('ok', false, 'error', 'No podés usar tu propio código.');
  end if;

  select id
    into referrer_id
  from public.usuarios
  where codigo_referido = normalized_code;

  if referrer_id is null then
    return jsonb_build_object('ok', false, 'error', 'Ese código no existe.');
  end if;

  update public.usuarios
     set creditos = coalesce(creditos, 0) + 20
   where id = referrer_id;

  update public.usuarios
     set creditos = coalesce(creditos, 0) + 15,
         codigo_referido_usado = normalized_code
   where id = p_user_id;

  return jsonb_build_object('ok', true);
end;
$$;
