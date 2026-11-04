-- Vuelve atrás FEAT_mail_pago_estudio_2026-11-04.sql
drop trigger if exists trg_liquidacion_pagada_mail on public.liquidaciones;
drop function if exists public.liquidacion_pagada_mail();
drop trigger if exists trg_liquidaciones_exige_numero on public.liquidaciones;
drop function if exists public.liquidaciones_exige_numero();

-- La nota vuelve a su lugar original (texto completo).
update public.liquidaciones l
   set comprobante_nota = n.nota
  from public.liquidaciones_notas_internas n
 where n.liquidacion_id = l.id and l.comprobante_nota is null;

drop table if exists public.liquidaciones_notas_internas;
alter table public.liquidaciones
  drop column if exists numero_operacion,
  drop column if exists mail_pago_at,
  drop column if exists mail_pago_id,
  drop column if exists mail_pago_envios;
