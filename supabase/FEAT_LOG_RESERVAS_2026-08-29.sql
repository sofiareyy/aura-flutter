-- ============================================================================
-- LOG DE CAMBIOS DE ESTADO EN RESERVAS (item 20 del inventario)
--
-- Por qué existe: el 26/8 desaparecieron 3 reservas canceladas y NO se pudo
-- saber quién las borró ni cuándo — no había ningún rastro. El ledger de
-- créditos cuadraba, así que no se perdió plata, pero con reservas reales una
-- diferencia así no se puede explicar. Este log es la respuesta.
--
-- Diseño:
--  · Registra CREADA, cada cambio de ESTADO, y BORRADA (con el último estado).
--    El incidente fue un DELETE: un log solo-de-estados no lo habría visto.
--  · SIN foreign keys, a propósito: una FK con CASCADE borraría la historia
--    junto con la fila. El log tiene que sobrevivir a la reserva, a la clase
--    y a la usuaria.
--  · Guarda quién (auth.uid(), null si fue el cron/Aura) y como qué rol de
--    Postgres corría (authenticated / service_role / postgres): con eso se
--    distingue "la alumna canceló" de "lo hizo el cron" de "SQL directo".
--  · RLS sin policies: NADIE lee ni escribe desde el cliente. Escribe solo el
--    trigger (security definer); lee Aura por SQL/backoffice.
-- ============================================================================

create table if not exists public.reservas_estado_log (
  id              bigint generated always as identity primary key,
  reserva_id      bigint not null,
  clase_id        bigint,
  usuario_id      uuid,
  codigo_qr       text,
  accion          text not null check (accion in ('creada','estado','borrada')),
  estado_anterior text,
  estado_nuevo    text,
  hecho_por       uuid,          -- auth.uid(); null = cron / service_role / SQL
  hecho_como      text not null, -- current_user de Postgres
  created_at      timestamptz not null default now()
);

comment on table public.reservas_estado_log is
  'Historia inmutable de reservas: creación, cada cambio de estado y borrado. Sin FKs a propósito (debe sobrevivir a la reserva/clase/usuaria). Escribe sólo el trigger; se lee por SQL/backoffice. Motivo: el 26/8 se borraron 3 reservas sin dejar rastro.';

alter table public.reservas_estado_log enable row level security;
-- sin policies: cero acceso desde el cliente
revoke all on public.reservas_estado_log from anon, authenticated;
grant  all on public.reservas_estado_log to service_role;

create index if not exists reservas_estado_log_reserva_idx
  on public.reservas_estado_log (reserva_id, created_at);

create or replace function public.reservas_log_cambios()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.reservas_estado_log
      (reserva_id, clase_id, usuario_id, codigo_qr, accion, estado_anterior, estado_nuevo, hecho_por, hecho_como)
    values
      (new.id, new.clase_id, new.usuario_id, new.codigo_qr, 'creada', null, new.estado, auth.uid(), current_user);
    return new;
  elsif tg_op = 'UPDATE' then
    if new.estado is distinct from old.estado then
      insert into public.reservas_estado_log
        (reserva_id, clase_id, usuario_id, codigo_qr, accion, estado_anterior, estado_nuevo, hecho_por, hecho_como)
      values
        (new.id, new.clase_id, new.usuario_id, new.codigo_qr, 'estado', old.estado, new.estado, auth.uid(), current_user);
    end if;
    return new;
  else  -- DELETE: el caso del 26/8
    insert into public.reservas_estado_log
      (reserva_id, clase_id, usuario_id, codigo_qr, accion, estado_anterior, estado_nuevo, hecho_por, hecho_como)
    values
      (old.id, old.clase_id, old.usuario_id, old.codigo_qr, 'borrada', old.estado, null, auth.uid(), current_user);
    return old;
  end if;
end;
$$;

drop trigger if exists trg_reservas_log_cambios on public.reservas;
create trigger trg_reservas_log_cambios
  after insert or update or delete on public.reservas
  for each row execute function public.reservas_log_cambios();
