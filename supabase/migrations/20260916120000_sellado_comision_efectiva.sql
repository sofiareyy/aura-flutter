-- ============================================================================
-- El sellado de la comisión deja de mirar la fecha del PAGO (16/9/2026)
-- ============================================================================
--
-- Bug de plata: `liquidaciones_sella_comision` decidía la gracia con
-- `fecha_pago::date < fecha_inicio_cobro`. Agosto de Citra (3 clases, todas
-- antes del 13/9) se pagó el 16/9 y quedó sellado al 30%: $37.800 en vez de
-- $54.000. Pagado el 12/9 habría sellado 0%. El porcentaje dependía de cuándo
-- se tocaba el botón, no de cuándo se dieron las clases.
--
-- Desde ahora la gracia se decide POR RESERVA con la fecha de la CLASE (lo
-- hace el Dart/TS al armar `monto_a_pagar`), y un mes puede ser mixto (Citra
-- septiembre: hasta el 12/9 al 100%, desde el 13/9 al 70%). Un solo porcentaje
-- ya no describe el mes, así que la constancia guarda el % EFECTIVO que
-- realmente se aplicó, derivado de los montos que llegan a la fila:
--     comision_aplicada = (1 - monto_a_pagar / monto_total_reservas) × 100
-- Es exactamente lo que ya hacía el backfill del 28/8 para lo pagado antes.
-- Sigue congelándose una sola vez, al quedar 'pagado', y nunca se re-estampa.
-- ============================================================================

create or replace function public.liquidaciones_sella_comision()
returns trigger
language plpgsql
set search_path to 'public'
as $$
declare
  v_dc record;
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

  -- El % que se aplicó DE VERDAD, sacado de los montos de la fila. Respeta la
  -- gracia por clase y el mix clases/workshops sin tener que recalcular nada
  -- acá: la fórmula vive en un solo lugar (Liquidacion.netoReserva).
  if coalesce(new.monto_total_reservas, 0) > 0 then
    new.comision_aplicada := round(
      (1 - new.monto_a_pagar::numeric / new.monto_total_reservas) * 100, 2);
  else
    -- Sin bruto no hay de dónde derivar: queda la configurada, como constancia.
    new.comision_aplicada := coalesce(v_dc.comision_aura, 30);
  end if;

  -- Las de workshop y el valor del crédito son constancia de la config con la
  -- que se pagó; no deciden el monto (ya está en la fila).
  new.comision_workshop_aplicada := coalesce(v_dc.comision_workshop, 15);
  -- NULL en valor_credito significa "seguí el global" (decisión del 27/8), así
  -- que la constancia guarda el valor EFECTIVO, no el NULL.
  new.valor_credito_aplicado :=
    coalesce(v_dc.valor_credito, public.valor_credito_global());

  return new;
end;
$$;
