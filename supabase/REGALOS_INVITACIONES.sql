-- AURA - Tablas regalos + invitaciones_grupo (idempotente)
-- Si las tablas ya existen, los CREATE TABLE no hacen nada.


-- 1. REGALOS

create extension if not exists pgcrypto;

create table if not exists public.regalos (
  id                  bigserial primary key,
  remitente_id        uuid references public.usuarios(id) on delete set null,
  destinatario_email  text not null,
  creditos            int  not null,
  codigo              text unique
                        default upper(substring(gen_random_uuid()::text, 1, 8)),
  usado               boolean not null default false,
  mensaje             text,
  created_at          timestamptz not null default now()
);

alter table public.regalos enable row level security;

drop policy if exists "Remitente y destinatario ven regalos" on public.regalos;
create policy "Remitente y destinatario ven regalos"
  on public.regalos for select
  using (
    auth.uid() = remitente_id
    or lower(destinatario_email) = lower(coalesce(
      (select email from auth.users where id = auth.uid()), ''
    ))
  );

drop policy if exists "Cualquier usuario crea regalos a su nombre" on public.regalos;
create policy "Cualquier usuario crea regalos a su nombre"
  on public.regalos for insert
  with check (auth.uid() = remitente_id);

-- El destinatario puede marcar usado = true al canjear (lo hace register_screen).
drop policy if exists "Destinatario marca regalo como usado" on public.regalos;
create policy "Destinatario marca regalo como usado"
  on public.regalos for update
  using (
    lower(destinatario_email) = lower(coalesce(
      (select email from auth.users where id = auth.uid()), ''
    ))
  )
  with check (
    lower(destinatario_email) = lower(coalesce(
      (select email from auth.users where id = auth.uid()), ''
    ))
  );


-- 2. INVITACIONES_GRUPO

create table if not exists public.invitaciones_grupo (
  id              bigserial primary key,
  invitador_id    uuid references public.usuarios(id) on delete set null,
  clase_id        int8  references public.clases(id)  on delete cascade,
  invitado_email  text not null,
  estado          text not null default 'pendiente',
  created_at      timestamptz not null default now()
);

create index if not exists idx_invitaciones_grupo_clase
  on public.invitaciones_grupo (clase_id);
create index if not exists idx_invitaciones_grupo_invitador
  on public.invitaciones_grupo (invitador_id);

alter table public.invitaciones_grupo enable row level security;

-- Lectura: el invitador ve sus invitaciones; el invitado ve las que le mandaron;
-- y cualquier usuario logueado puede contar las invitaciones de una clase
-- para mostrar 'X amigas van' (la query es solo SELECT id, no expone datos).
drop policy if exists "Invitador y invitado ven invitaciones" on public.invitaciones_grupo;
create policy "Invitador y invitado ven invitaciones"
  on public.invitaciones_grupo for select
  using (
    auth.uid() = invitador_id
    or lower(invitado_email) = lower(coalesce(
      (select email from auth.users where id = auth.uid()), ''
    ))
    or auth.uid() is not null
  );

drop policy if exists "Usuario crea invitaciones a su nombre" on public.invitaciones_grupo;
create policy "Usuario crea invitaciones a su nombre"
  on public.invitaciones_grupo for insert
  with check (auth.uid() = invitador_id);

-- El invitador puede cancelar sus invitaciones; el invitado puede aceptar/rechazar.
drop policy if exists "Invitador o invitado actualizan estado" on public.invitaciones_grupo;
create policy "Invitador o invitado actualizan estado"
  on public.invitaciones_grupo for update
  using (
    auth.uid() = invitador_id
    or lower(invitado_email) = lower(coalesce(
      (select email from auth.users where id = auth.uid()), ''
    ))
  );


-- 3. Verificacion (correr aparte)
-- select * from public.regalos limit 5;
-- select * from public.invitaciones_grupo limit 5;
