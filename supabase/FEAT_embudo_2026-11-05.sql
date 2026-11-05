-- Embudo (5/11/2026): lo que necesita la base para medir de la landing a la compra.
--
-- 1. pagos: el navegador que abrió el checkout (identificador de GA y campaña),
--    para que la compra que confirma Mercado Pago se una en GA4 a la visita que
--    vino del anuncio. ga_compra_at = la compra ya se mandó a GA (una sola vez).
-- 2. embudo_pasos: la PRIMERA vez que cada cuenta vio clases y vio los packs.
--    Es lo único del embudo que la base no tenía. Registro, checkout y compra
--    ya estaban (auth.users y pagos).
-- 3. soy_cuenta_interna(): la app pregunta al iniciar sesión, y si es una cuenta
--    interna o de prueba, ese navegador deja de mandar datos a GA4.
-- 4. metricas.embudo: los pasos 4 a 8 por mes de registro.

begin;

-- ── 1. pagos ────────────────────────────────────────────────────────────────
alter table public.pagos
  add column if not exists ga_client_id text,
  add column if not exists ga_session_id text,
  add column if not exists atribucion jsonb,
  add column if not exists ga_compra_at timestamptz;

-- ── 2. embudo_pasos ─────────────────────────────────────────────────────────
create table if not exists public.embudo_pasos (
  usuario_id uuid not null references public.usuarios(id) on delete cascade,
  paso text not null check (paso in ('ver_clases', 'ver_packs')),
  plataforma text,
  primera_vez_at timestamptz not null default now(),
  primary key (usuario_id, paso)
);
alter table public.embudo_pasos enable row level security;
drop policy if exists "solo admin de Aura" on public.embudo_pasos;
create policy "solo admin de Aura" on public.embudo_pasos
  for select using (public.is_admin());
revoke all on public.embudo_pasos from anon;

-- La app anota el paso de la persona que tiene la sesión. Solo la primera vez.
create or replace function public.registrar_paso_embudo(p_paso text, p_plataforma text default null)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null or p_paso not in ('ver_clases', 'ver_packs') then return; end if;
  insert into public.embudo_pasos (usuario_id, paso, plataforma)
  values (auth.uid(), p_paso, left(p_plataforma, 10))
  on conflict (usuario_id, paso) do nothing;
end;
$$;
revoke all on function public.registrar_paso_embudo(text, text) from public, anon;
grant execute on function public.registrar_paso_embudo(text, text) to authenticated;

-- ── 3. soy_cuenta_interna ───────────────────────────────────────────────────
create or replace function public.soy_cuenta_interna()
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce(public.es_cuenta_interna(
    (select email from auth.users where id = auth.uid())), false);
$$;
revoke all on function public.soy_cuenta_interna() from public, anon;
grant execute on function public.soy_cuenta_interna() to authenticated;

-- ── 4. metricas.embudo ──────────────────────────────────────────────────────
-- Alumnas (sin cuentas internas ni de estudios) por mes de registro, y una fila
-- "Total". "Vio clases" y "Vio packs" se anotan desde el 5/11/2026: los meses
-- anteriores los muestran vacíos.
create or replace view metricas.embudo as
with alumnas as (
  select u.id, au.created_at
    from public.usuarios u
    join auth.users au on au.id = u.id
   where coalesce(u.rol, 'usuario') = 'usuario'
     and not public.es_cuenta_interna(au.email)
     and not public._vinculada_a_estudio(u.id)
),
pasos as (
  select a.id,
         to_char(a.created_at at time zone 'America/Argentina/Buenos_Aires', 'YYYY-MM') as mes,
         exists (select 1 from public.embudo_pasos e where e.usuario_id = a.id and e.paso = 'ver_clases') as vio_clases,
         exists (select 1 from public.embudo_pasos e where e.usuario_id = a.id and e.paso = 'ver_packs') as vio_packs,
         exists (select 1 from public.pagos p where p.user_id = a.id and p.type in ('pack', 'plan', 'gift')) as checkout,
         exists (select 1 from public.pagos p where p.user_id = a.id and p.status = 'approved') as compro
    from alumnas a
),
filas as (
  select mes, count(*) as registradas,
         count(*) filter (where vio_clases) as vieron_clases,
         count(*) filter (where vio_packs) as vieron_packs,
         count(*) filter (where checkout) as iniciaron_checkout,
         count(*) filter (where compro) as compraron
    from pasos group by mes
  union all
  select 'Total', count(*),
         count(*) filter (where vio_clases), count(*) filter (where vio_packs),
         count(*) filter (where checkout), count(*) filter (where compro)
    from pasos
)
select mes as mes_de_registro, registradas, vieron_clases, vieron_packs, iniciaron_checkout, compraron,
       round(100.0 * compraron / nullif(registradas, 0), 1) as pct_compraron
  from filas
 order by (mes = 'Total'), mes desc;
revoke all on metricas.embudo from anon, authenticated;

commit;
