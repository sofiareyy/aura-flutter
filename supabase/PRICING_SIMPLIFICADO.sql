-- AURA - Pricing simplificado (2026-04-28)
-- Un solo numero (valor_credito_ars) controla todos los precios.
-- Pack Prueba    : 20 cr  x valor x 1.00
-- Pack Esencial  : 50 cr  x valor x 0.95
-- Pack Popular   : 100 cr x valor x 0.90
-- Pack Full      : 200 cr x valor x 0.85


-- 1. Asegurar tabla configuracion_global (clave/valor)

create table if not exists public.configuracion_global (
  clave      text primary key,
  valor      text not null,
  updated_at timestamptz not null default now()
);

alter table public.configuracion_global enable row level security;

drop policy if exists "Admins leen config" on public.configuracion_global;
create policy "Admins leen config"
  on public.configuracion_global for select
  using (true);

drop policy if exists "Admins escriben config" on public.configuracion_global;
create policy "Admins escriben config"
  on public.configuracion_global for all
  using (
    exists (
      select 1 from public.admin_users where user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.admin_users where user_id = auth.uid()
    )
  );


-- 2. Insertar valor inicial (no pisa si ya existe)

insert into public.configuracion_global (clave, valor)
values ('valor_credito_ars', '1000')
on conflict (clave) do nothing;

insert into public.configuracion_global (clave, valor)
values (
  'creditos_por_categoria',
  '{"Gym/Funcional":10,"Pilates":14,"Yoga":18,"Ceramica + vino":50}'
)
on conflict (clave) do nothing;


-- 3. Funcion que recalcula los precios de los 4 packs base
--    desde el valor_credito_ars actual.

create or replace function public.recalc_pack_prices()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_valor numeric;
begin
  select valor::numeric
    into v_valor
    from public.configuracion_global
   where clave = 'valor_credito_ars';

  if v_valor is null or v_valor <= 0 then
    return;
  end if;

  -- Pack Prueba (20 cr) x 1.00
  update public.pricing_credit_packs
     set precio = round(20 * v_valor * 1.00)::bigint
   where creditos = 20;

  -- Pack Esencial (50 cr) x 0.95
  update public.pricing_credit_packs
     set precio = round(50 * v_valor * 0.95)::bigint
   where creditos = 50;

  -- Pack Popular (100 cr) x 0.90
  update public.pricing_credit_packs
     set precio = round(100 * v_valor * 0.90)::bigint
   where creditos = 100;

  -- Pack Full (200 cr) x 0.85
  update public.pricing_credit_packs
     set precio = round(200 * v_valor * 0.85)::bigint
   where creditos = 200;
end;
$$;


-- 4. RPC publico para admins: cambia el valor y recalcula todo

create or replace function public.admin_set_valor_credito_ars(p_value bigint)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.admin_users where user_id = auth.uid()
  ) then
    raise exception 'No autorizado';
  end if;

  if p_value is null or p_value <= 0 then
    raise exception 'El valor debe ser mayor a 0';
  end if;

  insert into public.configuracion_global (clave, valor, updated_at)
  values ('valor_credito_ars', p_value::text, now())
  on conflict (clave) do update
    set valor = excluded.valor,
        updated_at = now();

  perform public.recalc_pack_prices();

  -- Backwards compat: el dashboard anterior lee de estudios.valor_credito
  update public.estudios set valor_credito = p_value;
end;
$$;


-- 5. RPC para guardar creditos por categoria (JSON en configuracion_global)

create or replace function public.admin_set_creditos_por_categoria(p_json text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.admin_users where user_id = auth.uid()
  ) then
    raise exception 'No autorizado';
  end if;

  -- Validacion suave: que sea JSON parseable
  perform p_json::jsonb;

  insert into public.configuracion_global (clave, valor, updated_at)
  values ('creditos_por_categoria', p_json, now())
  on conflict (clave) do update
    set valor = excluded.valor,
        updated_at = now();
end;
$$;


-- 6. Aplicar el recalc inicial

select public.recalc_pack_prices();


-- 7. Verificacion (correr aparte para chequear)
-- select * from public.configuracion_global;
-- select nombre, creditos, precio, vencimiento_dias from public.pricing_credit_packs order by creditos;
