-- AURA — Datos reales para el análisis de margen (2026-08-13). Solo LEE.
-- Confirma los dos supuestos del cálculo: el valor del crédito y la comisión
-- que paga cada estudio.

-- 1) Valor base de 1 crédito. El análisis asume $1.000.
select clave, valor, updated_at
  from public.configuracion_global
 where clave = 'valor_credito_ars';

-- 2) La comisión REAL de cada estudio y su período de gracia.
--    `paga_al_estudio_por_credito` es lo que te cuesta cada crédito usado ahí.
--    Ojo con `en_gracia = true`: durante la gracia el estudio se lleva el 100%,
--    así que ese crédito te deja margen NEGATIVO.
select e.nombre,
       e.comision_aura                              as comision_aura_pct,
       e.comision_workshop                          as comision_workshop_pct,
       e.valor_credito                              as valor_credito_propio,
       e.fecha_inicio_cobro,
       (e.fecha_inicio_cobro is not null
        and e.fecha_inicio_cobro > current_date)     as en_gracia,
       case
         when e.fecha_inicio_cobro is not null
          and e.fecha_inicio_cobro > current_date
           then coalesce(e.valor_credito, 1000)
         else round(coalesce(e.valor_credito, 1000)
                    * (100 - coalesce(e.comision_aura, 30)) / 100.0)
       end                                          as paga_al_estudio_por_credito
  from public.estudios e
 where e.activo = true
 order by e.nombre;

-- 3) Resumen: ¿cuántos estudios están en gracia (margen negativo) hoy?
select count(*) filter (
         where fecha_inicio_cobro is not null
           and fecha_inicio_cobro > current_date
       )                                            as en_gracia,
       count(*) filter (
         where fecha_inicio_cobro is null
            or fecha_inicio_cobro <= current_date
       )                                            as cobrando_comision,
       count(*)                                     as total_activos
  from public.estudios
 where activo = true;
