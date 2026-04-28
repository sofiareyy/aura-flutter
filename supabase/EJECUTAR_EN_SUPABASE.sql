-- AURA - SQL ejecutado en Supabase (2026-04-28)
-- Esquema real de referrals: referrer_user_id, referred_user_id, referral_code (NOT NULL)


-- 1. FAVORITOS DE ESTUDIOS

create table if not exists favoritos_estudios (
  usuario_id  uuid        not null references usuarios(id) on delete cascade,
  estudio_id  int         not null references estudios(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (usuario_id, estudio_id)
);

alter table favoritos_estudios enable row level security;

drop policy if exists "Usuarios ven sus favoritos" on favoritos_estudios;
create policy "Usuarios ven sus favoritos"
  on favoritos_estudios for select
  using (auth.uid() = usuario_id);

drop policy if exists "Usuarios insertan favoritos" on favoritos_estudios;
create policy "Usuarios insertan favoritos"
  on favoritos_estudios for insert
  with check (auth.uid() = usuario_id);

drop policy if exists "Usuarios borran favoritos" on favoritos_estudios;
create policy "Usuarios borran favoritos"
  on favoritos_estudios for delete
  using (auth.uid() = usuario_id);


-- 2. COLUMNA estudio_id en usuarios (para roles estudio)

alter table usuarios
  add column if not exists estudio_id int references estudios(id) on delete set null;


-- 3. COLUMNA checked_in_at en reservas (para QR de asistencia)

alter table reservas
  add column if not exists checked_in_at timestamptz;


-- 4. COLUMNAS codigo_referido en usuarios

alter table usuarios
  add column if not exists codigo_referido       text unique,
  add column if not exists codigo_referido_usado text;


-- 5. UNIQUE constraint y RLS en referrals (tabla preexistente)

alter table referrals
  drop constraint if exists referrals_referrer_referred_unique;

alter table referrals
  add constraint referrals_referrer_referred_unique
  unique (referrer_user_id, referred_user_id);

alter table referrals enable row level security;

drop policy if exists "Usuarios ven sus referrals" on referrals;
create policy "Usuarios ven sus referrals"
  on referrals for select
  using (auth.uid() = referrer_user_id or auth.uid() = referred_user_id);


-- 6. RPC apply_referral_code (limite 2 referidos, +20 / +15 creditos)

create or replace function apply_referral_code(
  p_user_id uuid,
  p_code    text
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_referrer_id    uuid;
  v_already_used   text;
  v_referrer_count int;
  v_expiry         date := current_date + interval '30 days';
  v_code_upper     text := upper(p_code);
begin
  select codigo_referido_usado
    into v_already_used
    from usuarios
   where id = p_user_id;

  if v_already_used is not null and v_already_used <> '' then
    return jsonb_build_object('ok', false, 'error', 'Ya usaste un codigo de referido anteriormente.');
  end if;

  select id
    into v_referrer_id
    from usuarios
   where upper(codigo_referido) = v_code_upper
   limit 1;

  if v_referrer_id is null then
    return jsonb_build_object('ok', false, 'error', 'Codigo de referido invalido.');
  end if;

  if v_referrer_id = p_user_id then
    return jsonb_build_object('ok', false, 'error', 'No podes usar tu propio codigo de referido.');
  end if;

  select count(*)
    into v_referrer_count
    from referrals
   where referrer_user_id = v_referrer_id;

  if v_referrer_count >= 2 then
    return jsonb_build_object('ok', false, 'error', 'Este codigo ya alcanzo el limite de invitaciones.');
  end if;

  insert into referrals (referrer_user_id, referred_user_id, referral_code)
  values (v_referrer_id, p_user_id, v_code_upper)
  on conflict on constraint referrals_referrer_referred_unique do nothing;

  update usuarios
     set codigo_referido_usado = v_code_upper
   where id = p_user_id;

  perform grant_user_credits(
    p_user_id    => p_user_id,
    p_amount     => 15,
    p_source     => 'referral',
    p_expires_at => v_expiry::text
  );

  perform grant_user_credits(
    p_user_id    => v_referrer_id,
    p_amount     => 20,
    p_source     => 'referral',
    p_expires_at => v_expiry::text
  );

  return jsonb_build_object('ok', true);

exception when others then
  return jsonb_build_object('ok', false, 'error', sqlerrm);
end;
$$;


-- 7. RPC ensure_referral_code

create or replace function ensure_referral_code(p_user_id uuid)
returns text
language plpgsql
security definer
as $$
declare
  v_code text;
begin
  select codigo_referido into v_code
    from usuarios
   where id = p_user_id;

  if v_code is null or v_code = '' then
    v_code := upper(substring(replace(p_user_id::text, '-', ''), 1, 6)
              || to_char(floor(random() * 9999)::int, 'FM0000'));
    update usuarios set codigo_referido = v_code where id = p_user_id;
  end if;

  return v_code;
end;
$$;


-- 8. DIAGNOSTICO opcional - estudios sin coordenadas para el mapa
-- select id, nombre, lat, lng from estudios where lat is null or lng is null;
