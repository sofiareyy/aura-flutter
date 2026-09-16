-- ============================================================================
-- Asiento de corrección de una liquidación PAGADA (16/9/2026)
-- ============================================================================
--
-- Caso: agosto de Citra quedó sellado al 30% por el bug de la gracia
-- retroactiva ($37.800 en la fila) pero la transferencia real fue por los
-- $54.000 correctos. La fila no se puede tocar: el guard de pagadas la
-- protege, y eso está bien. Tampoco hay que saltear el guard.
--
-- Lo que se hace es lo que haría una contadora: un ASIENTO aparte que dice
-- "lo efectivamente pagado fue X, la fila decía Y, por este motivo, lo hizo
-- tal persona, tal día". La fila original queda intacta como constancia de
-- lo que pasó; las pantallas muestran fila + correcciones. Un asiento nunca
-- se edita ni se borra: si estuvo mal, se hace otro.
--
-- NO genera un pago pendiente: registra plata que ya se movió (o que se
-- reconoce como debida, según el motivo). Cobrar una diferencia es otra
-- operación, con su propio comprobante.
-- ============================================================================

create table if not exists public.liquidaciones_correcciones (
  id                  uuid primary key default gen_random_uuid(),
  liquidacion_id      uuid not null references public.liquidaciones(id) on delete restrict,
  estudio_id          bigint not null references public.estudios(id) on delete restrict,
  mes                 text not null,
  -- Lo que decía la liquidación (con las correcciones anteriores ya sumadas)
  -- y lo que efectivamente corresponde. La diferencia es el asiento.
  monto_registrado    bigint not null,
  monto_real          bigint not null,
  diferencia          bigint generated always as (monto_real - monto_registrado) stored,
  comision_registrada numeric,
  comision_real       numeric,
  motivo              text not null check (length(trim(motivo)) >= 10),
  hecho_por           uuid not null,
  created_at          timestamptz not null default now()
);

create index if not exists idx_liq_correcciones_liquidacion
  on public.liquidaciones_correcciones (liquidacion_id);
create index if not exists idx_liq_correcciones_estudio_mes
  on public.liquidaciones_correcciones (estudio_id, mes);

comment on table public.liquidaciones_correcciones is
  'Asientos de corrección sobre liquidaciones pagadas. La fila de liquidaciones no se toca; lo pagado real = monto_a_pagar + sum(diferencia). Inmutables.';

-- Mismos permisos de lectura que `liquidaciones`: el admin todo, el estudio
-- las suyas. Nadie escribe directo: sólo el RPC de abajo.
alter table public.liquidaciones_correcciones enable row level security;

drop policy if exists "admin lee correcciones" on public.liquidaciones_correcciones;
create policy "admin lee correcciones" on public.liquidaciones_correcciones
  for select to authenticated using (public.is_admin());

drop policy if exists "estudio ve sus correcciones" on public.liquidaciones_correcciones;
create policy "estudio ve sus correcciones" on public.liquidaciones_correcciones
  for select to authenticated using (public.es_miembro_de_estudio(estudio_id));

revoke all on public.liquidaciones_correcciones from anon, authenticated;
grant select on public.liquidaciones_correcciones to authenticated;

-- Un asiento no se edita ni se borra. Ni desde el dashboard.
create or replace function public.liquidaciones_correcciones_inmutables()
returns trigger language plpgsql as $$
begin
  raise exception 'Un asiento de corrección no se modifica ni se borra (id %). Si está mal, se hace otro.', old.id
    using errcode = 'check_violation';
end;
$$;

drop trigger if exists trg_liq_correcciones_inmutables on public.liquidaciones_correcciones;
create trigger trg_liq_correcciones_inmutables
  before update or delete on public.liquidaciones_correcciones
  for each row execute function public.liquidaciones_correcciones_inmutables();

-- ── El RPC ──────────────────────────────────────────────────────────────────
-- Sólo admin. Sólo sobre liquidaciones PAGADAS (una pendiente se recalcula
-- sola, no se corrige). Exige motivo. Deja rastro en admin_activity_logs.
create or replace function public.admin_corregir_liquidacion_pagada(
  p_liquidacion_id uuid,
  p_monto_real bigint,
  p_motivo text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_liq        record;
  v_registrado bigint;
  v_com_reg    numeric;
  v_com_real   numeric;
  v_id         uuid;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;
  if p_motivo is null or length(trim(p_motivo)) < 10 then
    raise exception 'El motivo es obligatorio (mínimo 10 caracteres)';
  end if;
  if p_monto_real is null or p_monto_real < 0 then
    raise exception 'Monto inválido';
  end if;

  select * into v_liq from public.liquidaciones where id = p_liquidacion_id;
  if not found then
    raise exception 'Liquidación % no existe', p_liquidacion_id;
  end if;
  if v_liq.estado <> 'pagado' then
    raise exception 'Sólo se corrige una liquidación PAGADA; una pendiente se recalcula sola';
  end if;

  -- Lo que "dice" hoy: la fila más las correcciones anteriores.
  select v_liq.monto_a_pagar + coalesce(sum(diferencia), 0)
    into v_registrado
    from public.liquidaciones_correcciones
   where liquidacion_id = p_liquidacion_id;

  if v_registrado = p_monto_real then
    raise exception 'La liquidación ya dice % — no hay nada que corregir', p_monto_real;
  end if;

  v_com_reg := case when coalesce(v_liq.monto_total_reservas, 0) > 0
                 then round((1 - v_registrado::numeric / v_liq.monto_total_reservas) * 100, 2) end;
  v_com_real := case when coalesce(v_liq.monto_total_reservas, 0) > 0
                 then round((1 - p_monto_real::numeric / v_liq.monto_total_reservas) * 100, 2) end;

  insert into public.liquidaciones_correcciones
    (liquidacion_id, estudio_id, mes, monto_registrado, monto_real,
     comision_registrada, comision_real, motivo, hecho_por)
  values
    (p_liquidacion_id, v_liq.estudio_id, v_liq.mes, v_registrado, p_monto_real,
     v_com_reg, v_com_real, trim(p_motivo), auth.uid())
  returning id into v_id;

  perform public.log_admin_action(
    'corregir_liquidacion',
    format('liquidacion=%s estudio=%s mes=%s registrado=%s real=%s diferencia=%s motivo=%s',
           p_liquidacion_id, v_liq.estudio_id, v_liq.mes, v_registrado, p_monto_real,
           p_monto_real - v_registrado, trim(p_motivo)),
    'liquidaciones');

  return jsonb_build_object(
    'ok', true, 'correccion_id', v_id,
    'monto_registrado', v_registrado, 'monto_real', p_monto_real,
    'diferencia', p_monto_real - v_registrado,
    'comision_registrada', v_com_reg, 'comision_real', v_com_real);
end;
$$;

revoke execute on function public.admin_corregir_liquidacion_pagada(uuid, bigint, text) from public, anon;
grant execute on function public.admin_corregir_liquidacion_pagada(uuid, bigint, text) to authenticated;
