-- 29/10/2026: 20% off en la PRIMERA compra de créditos de cada persona.
--
-- Reglas (decididas por Sofía):
--   · Una sola vez por persona, en cualquier pack. Gift cards: sin descuento y
--     NO cuentan como compra (quien regala conserva su descuento).
--   · Se aplica en el servidor ANTES de mandar a Mercado Pago
--     (crear-checkout-pack). La app sólo lo muestra.
--   · El porcentaje vive en UN lugar: configuracion_global
--     'descuento_primera_compra_pct'. '0' lo apaga en todos lados sin build.
--   · Cerrado también por mail: una cuenta borrada y vuelta a crear con el
--     mismo mail no lo recibe de nuevo. Como borrar la cuenta anonimiza el
--     mail, se guarda sólo su huella (sha256), nunca el mail en claro.
--
-- Para volver atrás: ROLLBACK_descuento_primera_compra_2026-10-29.sql

-- ── 1. El porcentaje ────────────────────────────────────────────────────────
insert into public.configuracion_global (clave, valor)
values ('descuento_primera_compra_pct', '20')
on conflict (clave) do nothing;

-- ── 2. Qué descuento llevó cada pago ────────────────────────────────────────
-- `amount` sigue siendo lo cobrado. precio_lista = lo que valía el pack.
alter table public.pagos
  add column if not exists precio_lista integer,
  add column if not exists descuento_pct integer not null default 0;

-- ── 3. Huella del mail de quien ya compró ──────────────────────────────────
create table if not exists public.compradores_huella (
  email_hash        text primary key,
  primera_compra_at timestamptz not null default now()
);
-- Sin políticas: nadie la lee ni la escribe desde la app.
alter table public.compradores_huella enable row level security;
revoke all on public.compradores_huella from anon, authenticated;

create or replace function public._huella_email(p_email text)
 returns text
 language sql
 immutable
 set search_path to 'public'
as $function$
  select encode(extensions.digest(lower(btrim(p_email)), 'sha256'), 'hex')
$function$;
revoke all on function public._huella_email(text) from public, anon, authenticated;

-- Cada vez que una compra de créditos (pack o plan) queda aprobada, se anota
-- la huella del mail. Nunca rompe un pago: si algo falla, sigue de largo.
create or replace function public.pagos_registra_huella_comprador()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_email text;
begin
  if new.type in ('pack', 'plan')
     and new.status = 'approved'
     and (tg_op = 'INSERT' or old.status is distinct from 'approved') then
    select email into v_email from auth.users where id = new.user_id;
    if v_email is not null and btrim(v_email) <> '' then
      insert into public.compradores_huella (email_hash)
      values (public._huella_email(v_email))
      on conflict (email_hash) do nothing;
    end if;
  end if;
  return new;
exception when others then
  return new;
end;
$function$;
revoke all on function public.pagos_registra_huella_comprador() from public, anon, authenticated;

drop trigger if exists trg_pagos_huella_comprador on public.pagos;
create trigger trg_pagos_huella_comprador
  after insert or update of status on public.pagos
  for each row execute function public.pagos_registra_huella_comprador();

-- Las compras que ya existen (las cuentas borradas ya no tienen mail: esas se
-- pierden, no hay forma de recuperarlas).
insert into public.compradores_huella (email_hash, primera_compra_at)
select public._huella_email(au.email), min(p.created_at)
  from public.pagos p
  join auth.users au on au.id = p.user_id
 where p.type in ('pack', 'plan')
   and (p.status = 'approved' or p.credits_granted_at is not null)
   and au.email is not null
 group by 1
on conflict (email_hash) do nothing;

-- ── 4. La regla: ¿cuánto descuento tiene esta persona? ─────────────────────
-- Devuelve el porcentaje o 0. Es la ÚNICA que decide; el checkout y la app
-- preguntan acá.
create or replace function public.descuento_primera_compra(p_user uuid)
 returns integer
 language plpgsql
 stable
 security definer
 set search_path to 'public'
as $function$
declare
  v_pct   int;
  v_email text;
begin
  if p_user is null then
    return 0;
  end if;

  select case when valor ~ '^\s*\d+\s*$' then btrim(valor)::int else 0 end
    into v_pct
    from public.configuracion_global
   where clave = 'descuento_primera_compra_pct';
  if coalesce(v_pct, 0) <= 0 or v_pct >= 100 then
    return 0;
  end if;

  -- Ya compró créditos para sí (pack o plan). Se mira `approved` además de
  -- credits_granted_at porque hay compras viejas aprobadas sin esa marca.
  -- Las gift cards no cuentan.
  if exists (
    select 1 from public.pagos
     where user_id = p_user
       and type in ('pack', 'plan')
       and (status = 'approved' or credits_granted_at is not null)
  ) then
    return 0;
  end if;
  if exists (
    select 1 from public.creditos_movimientos
     where user_id = p_user and source = 'pack'
  ) then
    return 0;
  end if;

  -- El mismo mail ya compró con otra cuenta (borrada y vuelta a crear).
  select email into v_email from auth.users where id = p_user;
  if v_email is not null and exists (
    select 1 from public.compradores_huella
     where email_hash = public._huella_email(v_email)
  ) then
    return 0;
  end if;

  -- Tiene un pago CON descuento que Mercado Pago todavía está procesando
  -- (tarjeta en revisión). Mientras tanto, otra compra va a precio lleno; si
  -- ese pago se rechaza, el descuento vuelve solo.
  -- Los checkouts abiertos y no pagados no tienen mp_payment_id: no cuentan.
  if exists (
    select 1 from public.pagos
     where user_id = p_user
       and type = 'pack'
       and descuento_pct > 0
       and mp_payment_id is not null
       and status in ('pending', 'in_process', 'authorized', 'in_mediation')
  ) then
    return 0;
  end if;

  return v_pct;
end;
$function$;
revoke all on function public.descuento_primera_compra(uuid) from public, anon, authenticated;
grant execute on function public.descuento_primera_compra(uuid) to service_role;

-- La app pregunta por la persona logueada, nunca por otra.
create or replace function public.mi_descuento_primera_compra()
 returns integer
 language sql
 stable
 security definer
 set search_path to 'public'
as $function$
  select public.descuento_primera_compra(auth.uid())
$function$;
revoke all on function public.mi_descuento_primera_compra() from public, anon;
grant execute on function public.mi_descuento_primera_compra() to authenticated;
