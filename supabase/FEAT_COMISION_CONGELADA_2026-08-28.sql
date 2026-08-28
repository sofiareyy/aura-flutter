-- ============================================================================
-- 1 · CONSTANCIA DE LA COMISIÓN EN CADA LIQUIDACIÓN PAGADA
--
-- Regla de la usuaria: cambiar la comisión de un estudio afecta SÓLO al
-- futuro. Un mes ya pagado queda como constancia con la comisión que tenía.
--
-- El problema medido el 27/8: `liquidaciones` guarda `monto_a_pagar` pero NO
-- la comisión ni el valor del crédito, y la pantalla **recalcula todo en vivo**
-- con la comisión ACTUAL. Bajarle hoy la comisión a un estudio cambiaba lo que
-- se muestra para meses ya pagados (medido con Citra: 37.800 -> 43.200).
--
-- Por qué un TRIGGER y no que lo mande el cliente: la fila de liquidación la
-- crea un INSERT directo desde `admin_liquidaciones_screen.dart`. Si dependiera
-- del Dart, esto esperaría al build 27. Con el trigger, la constancia queda
-- desde hoy y para cualquier camino que registre un pago.
-- ============================================================================

alter table public.liquidaciones
  add column if not exists comision_aplicada          numeric,
  add column if not exists valor_credito_aplicado     integer,
  add column if not exists comision_workshop_aplicada integer;

comment on column public.liquidaciones.comision_aplicada is
  'CONSTANCIA: % de comisión que se aplicó cuando se pagó este mes. Lo estampa el trigger al marcar pagado; después NO se toca aunque cambie la comisión del estudio. 0 = el estudio estaba en período de gracia.';
comment on column public.liquidaciones.valor_credito_aplicado is
  'CONSTANCIA: valor del crédito en ARS al momento del pago (el propio del estudio, o el global si no tenía uno).';
comment on column public.liquidaciones.comision_workshop_aplicada is
  'CONSTANCIA: % de comisión de experiencias/workshops al momento del pago.';

create or replace function public.liquidaciones_sella_comision()
returns trigger
language plpgsql
set search_path to 'public'
as $$
declare
  v_dc      record;
  v_inicio  date;
  v_engracia boolean;
begin
  -- Sólo al quedar PAGADO. Una liquidación pendiente todavía se recalcula, que
  -- es lo correcto: mientras no se pagó, el número puede cambiar.
  if coalesce(new.estado,'') <> 'pagado' then
    return new;
  end if;

  -- Congelado es congelado: si ya tiene constancia, no se re-estampa nunca
  -- (ni al editar la nota del comprobante, ni al re-marcar pagado).
  if new.comision_aplicada is not null then
    return new;
  end if;

  select dc.comision_aura, dc.comision_workshop, dc.valor_credito
    into v_dc
    from public.estudios_datos_cobro dc
   where dc.estudio_id = new.estudio_id;

  select e.fecha_inicio_cobro into v_inicio
    from public.estudios e where e.id = new.estudio_id;

  -- Mismo criterio que `Liquidacion.cobraComision` del Dart: antes de
  -- `fecha_inicio_cobro` Aura no cobra y el estudio recibe el 100%. Se evalúa
  -- con la fecha del PAGO, que es cuando la plata se movió de verdad.
  v_engracia := v_inicio is not null
                and (coalesce(new.fecha_pago, now()))::date < v_inicio;

  new.comision_aplicada := case
    when v_engracia then 0
    else coalesce(v_dc.comision_aura, 30)
  end;
  new.comision_workshop_aplicada := case
    when v_engracia then 0
    else coalesce(v_dc.comision_workshop, 15)
  end;
  -- NULL en valor_credito significa "seguí el global" (decisión del 27/8), así
  -- que la constancia guarda el valor EFECTIVO, no el NULL.
  new.valor_credito_aplicado :=
    coalesce(v_dc.valor_credito, public.valor_credito_global());

  return new;
end;
$$;

drop trigger if exists trg_liquidaciones_sella_comision on public.liquidaciones;
create trigger trg_liquidaciones_sella_comision
  before insert or update on public.liquidaciones
  for each row execute function public.liquidaciones_sella_comision();

-- Backfill de lo ya pagado: se deriva de sus PROPIOS montos, que es exacto y
-- no depende de suponer qué comisión regía en esa fecha.
--   comisión = (1 - monto_a_pagar / monto_total_reservas) * 100
-- El valor del crédito no se puede derivar sin la cantidad de créditos, así
-- que se toma el efectivo de hoy (1000, igual para los 11 estudios).
update public.liquidaciones l
   set comision_aplicada = round(
         (1 - (l.monto_a_pagar::numeric / nullif(l.monto_total_reservas,0))) * 100, 2),
       valor_credito_aplicado = coalesce(
         (select dc.valor_credito from public.estudios_datos_cobro dc
           where dc.estudio_id = l.estudio_id),
         public.valor_credito_global()),
       comision_workshop_aplicada = coalesce(
         (select dc.comision_workshop from public.estudios_datos_cobro dc
           where dc.estudio_id = l.estudio_id), 15)
 where l.estado = 'pagado'
   and l.comision_aplicada is null
   and coalesce(l.monto_total_reservas,0) > 0;
