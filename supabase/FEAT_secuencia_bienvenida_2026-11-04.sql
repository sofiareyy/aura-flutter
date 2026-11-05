-- Secuencia de bienvenida: 3 mails para quien se registra y no compra (4/11/2026).
--
--   Mail 1: al registrarse (a los 5 minutos, para que el perfil ya tenga nombre).
--   Mail 2: a los 4 días, si no compró.
--   Mail 3: a los 30 días, si no compró.
--
-- Queda APAGADA. Se prende con:
--   update public.secuencia_config set activa = true, desde = now(), updated_at = now();
-- y se apaga con:
--   update public.secuencia_config set activa = false, updated_at = now();
--
-- A quién NO le llega (se revisa en el momento de mandar cada mail, así que si
-- compra o se da de baja entre un mail y otro, no recibe los que faltan):
--   · quien compró (un pago aprobado, o un plan que pagó y después canceló);
--   · cuentas internas y de prueba (cuentas_internas);
--   · cuentas de estudios y profes (_vinculada_a_estudio);
--   · cualquier dirección en mail_bajas: se dio de baja, rebotó o marcó spam;
--   · quienes están en el sorteo de noviembre (regalo_campana): a ellas les
--     escribe la campaña, y el envío único a las 80 es aparte, después del 17/11.
--
-- Quién entra:
--   · Mails 1 y 2: solo cuentas creadas desde que se prende.
--   · Mail 3: también las creadas en los 30 días anteriores a prenderla, cuando
--     cumplen los 30 días (es lo que se acordó: las recientes no van al envío
--     único, les llega solo).
--   Cada mail tiene una ventana corta (mail 1: 2 días; mail 2: días 4 a 7;
--   mail 3: días 30 a 33). Si algo se cae unos días, no sale un mail viejo fuera
--   de tiempo ni se juntan dos el mismo día.

begin;

-- ── Interruptor ──────────────────────────────────────────────────────────────
create table if not exists public.secuencia_config (
  id boolean primary key default true check (id),
  activa boolean not null default false,
  desde timestamptz,
  updated_at timestamptz not null default now()
);
insert into public.secuencia_config (id) values (true) on conflict do nothing;
alter table public.secuencia_config enable row level security;
drop policy if exists "solo admin de Aura" on public.secuencia_config;
create policy "solo admin de Aura" on public.secuencia_config
  for all using (public.is_admin()) with check (public.is_admin());

-- ── Qué se mandó ─────────────────────────────────────────────────────────────
create table if not exists public.secuencia_mails (
  usuario_id uuid not null references public.usuarios(id) on delete cascade,
  paso smallint not null check (paso between 1 and 3),
  email text not null,
  estado text not null default 'enviando',   -- enviando | enviado | error: ...
  resend_id text,
  intentos int not null default 1,
  created_at timestamptz not null default now(),
  enviado_at timestamptz,
  primary key (usuario_id, paso)
);
alter table public.secuencia_mails enable row level security;
drop policy if exists "solo admin de Aura" on public.secuencia_mails;
create policy "solo admin de Aura" on public.secuencia_mails
  for select using (public.is_admin());

-- ── A quién le toca un mail ahora ────────────────────────────────────────────
create or replace function public.secuencia_a_enviar(p_limite int default 50)
returns table (usuario_id uuid, paso smallint, email text, nombre text)
language sql stable security definer set search_path = public
as $$
  with cfg as (
    select desde from public.secuencia_config where activa and desde is not null
  ),
  base as (
    select u.id, lower(trim(au.email)) as email, u.nombre, au.created_at, cfg.desde
      from public.usuarios u
      join auth.users au on au.id = u.id
      cross join cfg
     where au.created_at >= cfg.desde - interval '30 days'
       and coalesce(u.rol, 'usuario') = 'usuario'
       and au.email like '%@%'
       and au.email not like '%@cuenta-eliminada.aura'
       and not public.es_cuenta_interna(au.email)
       and not public._vinculada_a_estudio(u.id)
       and not exists (select 1 from public.mail_bajas b where b.email = lower(trim(au.email)))
       and not exists (select 1 from public.pagos p
                        where p.user_id = u.id and p.status in ('approved', 'cancelled'))
       and not exists (select 1 from public.regalo_campana rc where rc.usuario_id = u.id)
  ),
  cand as (
    select b.*,
      case
        when now() >= b.created_at + interval '30 days'
         and now() <  b.created_at + interval '33 days' then 3
        when b.created_at >= b.desde
         and now() >= b.created_at + interval '4 days'
         and now() <  b.created_at + interval '7 days' then 2
        when b.created_at >= b.desde
         and now() >= b.created_at + interval '5 minutes'
         and now() <  b.created_at + interval '2 days' then 1
      end::smallint as paso
    from base b
  )
  select c.id, c.paso, c.email, c.nombre
    from cand c
   where c.paso is not null
     and not exists (select 1 from public.secuencia_mails m
                      where m.usuario_id = c.id and m.paso = c.paso
                        and (m.estado not like 'error%' or m.intentos >= 3))
   order by c.created_at
   limit p_limite;
$$;

-- ── Tomar un mail antes de mandarlo (dos llamadas a la vez no mandan dos) ────
-- Devuelve true si esta llamada lo tiene que mandar. Un error se reintenta
-- hasta 3 veces en total.
create or replace function public.secuencia_tomar(p_usuario_id uuid, p_paso smallint, p_email text)
returns boolean
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.secuencia_mails (usuario_id, paso, email)
  values (p_usuario_id, p_paso, p_email)
  on conflict (usuario_id, paso) do update
     set intentos = public.secuencia_mails.intentos + 1,
         estado = 'enviando',
         email = excluded.email
   where public.secuencia_mails.estado like 'error%'
     and public.secuencia_mails.intentos < 3;
  return found;
end;
$$;

revoke all on function public.secuencia_a_enviar(int) from public, anon, authenticated;
revoke all on function public.secuencia_tomar(uuid, smallint, text) from public, anon, authenticated;
grant execute on function public.secuencia_a_enviar(int) to service_role;
grant execute on function public.secuencia_tomar(uuid, smallint, text) to service_role;

-- ── El reloj: cada 10 minutos, si hay algo para mandar, llama a la función ──
create or replace function public.secuencia_tick()
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_secret text;
  v_url  text := 'https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/secuencia-email';
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2Z3FwenZvcm5sbnhtc2JxbndnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwNzcxMjIsImV4cCI6MjA5MDY1MzEyMn0.G5AKWyFGoL8j6IfAZV40U6TceaoQc0oVPYpepiIyDlk';
begin
  if not exists (select 1 from public.secuencia_a_enviar(1)) then return; end if;
  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'notif_trigger_secret';
  if coalesce(v_secret, '') = '' then return; end if;
  perform net.http_post(
    url     := v_url,
    headers := jsonb_build_object(
      'Content-Type',   'application/json',
      'Authorization',  'Bearer ' || v_anon,
      'apikey',         v_anon,
      'x-notif-secret', v_secret),
    body    := '{}'::jsonb,
    timeout_milliseconds := 120000);
end;
$$;
revoke all on function public.secuencia_tick() from public, anon, authenticated;

select cron.schedule('secuencia-bienvenida', '*/10 * * * *', 'select public.secuencia_tick()');

-- ── Para medir: Table Editor → schema metricas → secuencia_resumen ──────────
create or replace view metricas.secuencia_resumen as
select m.paso,
       count(*) filter (where m.estado = 'enviado') as enviados,
       count(*) filter (where m.estado like 'error%') as con_error,
       count(*) filter (where m.estado = 'enviado' and exists (
         select 1 from public.pagos p
          where p.user_id = m.usuario_id and p.status in ('approved', 'cancelled')
            and p.created_at > m.enviado_at)) as compraron_despues
  from public.secuencia_mails m
 group by m.paso
 order by m.paso;
revoke all on metricas.secuencia_resumen from anon, authenticated;
revoke all on public.secuencia_config, public.secuencia_mails from anon;

commit;
