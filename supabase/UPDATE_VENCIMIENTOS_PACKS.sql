-- AURA - Actualizar vencimientos de packs (2026-04-28)
-- Pack Prueba (20 cr): 30 dias (antes 60)
-- Pack Esencial (50 cr) / Popular (100 cr) / Full (200 cr): 60 dias (antes 90)


-- 1. Actualizar tabla pricing_credit_packs

update public.pricing_credit_packs set vencimiento_dias = 30 where creditos = 20;
update public.pricing_credit_packs set vencimiento_dias = 60 where creditos in (50, 100, 200);


-- 2. Funcion pack_credits_expiration (si existe la usan los flows de pagos)
-- Esta version cubre tambien el caso de packs personalizados via tabla.

create or replace function public.pack_credits_expiration(
  p_pack_nombre text default null,
  p_creditos    integer default null
)
returns integer
language plpgsql
stable
as $$
declare
  v_dias integer;
begin
  -- 1. Buscar en pricing_credit_packs por nombre o creditos
  select vencimiento_dias
    into v_dias
    from public.pricing_credit_packs
   where coalesce(activo, true) = true
     and (
       (p_pack_nombre is not null and lower(nombre) = lower(p_pack_nombre))
       or (p_creditos is not null and creditos = p_creditos)
     )
   order by case when p_pack_nombre is not null and lower(nombre) = lower(p_pack_nombre) then 0 else 1 end
   limit 1;

  if v_dias is not null and v_dias > 0 then
    return v_dias;
  end if;

  -- 2. Fallback por creditos: <= 20 -> 30 dias, sino 60
  if coalesce(p_creditos, 0) <= 20 then
    return 30;
  end if;
  return 60;
end;
$$;


-- 3. Si existe una tabla packs_config separada, actualizar tambien
-- (no falla si la tabla no existe; el DO block la ignora)

do $$
begin
  if exists (
    select 1
      from information_schema.tables
     where table_schema = 'public'
       and table_name = 'packs_config'
  ) then
    execute 'update public.packs_config set vencimiento_dias = 30 where creditos = 20';
    execute 'update public.packs_config set vencimiento_dias = 60 where creditos in (50, 100, 200)';
  end if;
end$$;


-- 4. Verificacion (correr aparte para chequear)
-- select nombre, creditos, vencimiento_dias from public.pricing_credit_packs order by creditos;
-- select pack_credits_expiration('Pack Prueba', 20);    -- 30
-- select pack_credits_expiration('Pack Esencial', 50);  -- 60
-- select pack_credits_expiration('Pack Popular', 100);  -- 60
-- select pack_credits_expiration('Pack Full', 200);     -- 60
