-- ============================================================
-- AURA - SQL para ejecutar en Supabase SQL Editor
-- Orden: ejecutar todo de una vez o sección por sección
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. FAVORITOS DE ESTUDIOS
-- ─────────────────────────────────────────────────────────────
create table if not exists favoritos_estudios (
  usuario_id  uuid        not null references usuarios(id) on delete cascade,
  estudio_id  int         not null references estudios(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (usuario_id, estudio_id)
);

-- RLS
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


-- ─────────────────────────────────────────────────────────────
-- 2. COLUMNA estudio_id EN USUARIOS (para roles estudio)
-- ─────────────────────────────────────────────────────────────
alter table usuarios
  add column if not exists estudio_id int references estudios(id) on delete set null;


-- ─────────────────────────────────────────────────────────────
-- 3. COLUMNA checked_in_at EN RESERVAS (para QR de asistencia)
-- ─────────────────────────────────────────────────────────────
alter table reservas
  add column if not exists checked_in_at timestamptz;


-- ─────────────────────────────────────────────────────────────
-- 4. RPC apply_referral_code — LÍMITE 2 REFERIDOS
--    Premio: quien refiere +20 créditos, nuevo usuario +15
-- ─────────────────────────────────────────────────────────────
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
begin
  -- Verificar que el usuario no haya usado ya un código
  select codigo_referido_usado
    into v_already_used
    from usuarios
   where id = p_user_id;

  if v_already_used is not null and v_already_used <> '' then
    return jsonb_build_object('ok', false, 'error', 'Ya usaste un código de referido anteriormente.');
  end if;

  -- Buscar al dueño del código
  select id
    into v_referrer_id
    from usuarios
   where upper(codigo_referido) = upper(p_code)
   limit 1;

  if v_referrer_id is null then
    return jsonb_build_object('ok', false, 'error', 'Código de referido inválido.');
  end if;

  -- No puede usar su propio código
  if v_referrer_id = p_user_id then
    return jsonb_build_object('ok', false, 'error', 'No podés usar tu propio código de referido.');
  end if;

  -- Verificar que el referrer no superó el límite de 2
  select count(*)
    into v_referrer_count
    from referrals
   where referrer_id = v_referrer_id;

  if v_referrer_count >= 2 then
    return jsonb_build_object('ok', false, 'error', 'Este código ya alcanzó el límite de invitaciones.');
  end if;

  -- Registrar el referido
  insert into referrals (referrer_id, referred_id)
  values (v_referrer_id, p_user_id)
  on conflict do nothing;

  -- Marcar el código como usado en el nuevo usuario
  update usuarios
     set codigo_referido_usado = upper(p_code)
   where id = p_user_id;

  -- Dar 15 créditos al nuevo usuario
  perform grant_user_credits(
    p_user_id    => p_user_id,
    p_amount     => 15,
    p_source     => 'referral',
    p_expires_at => v_expiry::text
  );

  -- Dar 20 créditos al referidor
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


-- ─────────────────────────────────────────────────────────────
-- 5. RPC ensure_referral_code (crea el código si no existe)
-- ─────────────────────────────────────────────────────────────
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
    -- Generar código: 8 chars en mayúscula basados en uuid + random
    v_code := upper(substring(replace(p_user_id::text, '-', ''), 1, 6)
              || to_char(floor(random() * 9999)::int, 'FM0000'));
    update usuarios set codigo_referido = v_code where id = p_user_id;
  end if;

  return v_code;
end;
$$;


-- ─────────────────────────────────────────────────────────────
-- 6. ASEGURARSE que columna codigo_referido existe en usuarios
-- ─────────────────────────────────────────────────────────────
alter table usuarios
  add column if not exists codigo_referido       text unique,
  add column if not exists codigo_referido_usado text;


-- ─────────────────────────────────────────────────────────────
-- 7. VERIFICAR lat/lng en estudios (diagnóstico)
-- ─────────────────────────────────────────────────────────────
-- Ejecutá esta query para ver qué estudios les faltan coordenadas:
-- select id, nombre, lat, lng from estudios where lat is null or lng is null;
--
-- Coordenadas aproximadas de los estudios conocidos:
-- UPDATE estudios SET lat = -34.4644, lng = -58.9134 WHERE nombre ILIKE '%Clic Fit%' AND direccion ILIKE '%Office Park%';
-- UPDATE estudios SET lat = -34.4632, lng = -58.9055 WHERE nombre ILIKE '%Clic Fit%' AND direccion ILIKE '%Austral%';
-- UPDATE estudios SET lat = -34.3831, lng = -58.9643 WHERE nombre ILIKE '%Clic Fit%' AND direccion ILIKE '%Tortugitas%';
-- UPDATE estudios SET lat = -34.4644, lng = -58.9134 WHERE nombre ILIKE '%Clic Pilates%';
-- UPDATE estudios SET lat = -34.4644, lng = -58.9134 WHERE nombre ILIKE '%Hot Clic%';
-- UPDATE estudios SET lat = -34.4712, lng = -58.8954 WHERE nombre ILIKE '%Kali Yoga%';
-- UPDATE estudios SET lat = -34.4580, lng = -58.9003 WHERE nombre ILIKE '%Sport Club%';
-- UPDATE estudios SET lat = -34.4630, lng = -58.8990 WHERE nombre ILIKE '%Grito%';
