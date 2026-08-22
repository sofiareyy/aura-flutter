-- ============================================================================
-- AURA — Monitoreo de arbitraje de comisión en workshops
-- ============================================================================
-- (2026-08-22) Arreglo 5 de 5 de la tanda de control de pricing.
-- SOLO LEE. No bloquea nada, no cambia nada. Correr cuando quieras.
--
-- QUÉ VIGILA
-- Un workshop paga 15% de comisión; una clase normal paga ~30%. Un estudio
-- podría cargar sus clases regulares como workshops para pagar la mitad.
--
-- POR QUÉ SÓLO MIRAR Y NO BLOQUEAR
-- Hoy hay tres frenos suficientes:
--   1. rol: un trigger impide que una profe cree o edite workshops
--   2. tope: el CHECK `clases_creditos_sanos` limita a 500 créditos
--   3. y el más fuerte: LOS WORKSHOPS NO PUEDEN SER RECURRENTES. No existe
--      `horarios_fijos.tipo`, así que cada workshop es una clase individual
--      con fecha propia, cargada a mano. Para pasar una grilla semanal al 15%
--      habría que cargar cada ocurrencia una por una, sin generador.
-- Ese tercer freno es un activo de negocio, no deuda técnica. No agregarle
-- recurrencia a los workshops.
--
-- Lo que falta no es un freno más: es la señal de patrón, que hoy no existe.
-- El dashboard y liquidaciones ya separan workshops de clases, así que hay
-- visibilidad de PLATA pero ninguna alarma de COMPORTAMIENTO.
-- ============================================================================


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 1) WORKSHOPS QUE HUELEN A GRILLA                                         │
-- │    Mismo estudio, mismo nombre, mismo día de semana y misma hora,        │
-- │    repetido 3 veces o más. Eso es una clase recurrente disfrazada.       │
-- └──────────────────────────────────────────────────────────────────────────┘
select e.nombre                                as estudio,
       c.nombre                                as workshop,
       case extract(isodow from c.fecha)::int
         when 1 then 'lunes'  when 2 then 'martes' when 3 then 'miércoles'
         when 4 then 'jueves' when 5 then 'viernes' when 6 then 'sábado'
         else 'domingo' end                    as dia,
       to_char(c.fecha, 'HH24:MI')             as hora,
       count(*)                                as repeticiones,
       min(c.fecha)::date                      as desde,
       max(c.fecha)::date                      as hasta
  from public.clases c
  join public.estudios e on e.id = c.estudio_id
 where coalesce(c.tipo, 'clase') = 'workshop'
 group by e.nombre, c.nombre, extract(isodow from c.fecha), to_char(c.fecha, 'HH24:MI')
having count(*) >= 3
 order by count(*) desc;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 2) WORKSHOPS CON PRECIO DE CLASE                                         │
-- │    Una experiencia real cuesta bastante más que una clase suelta. Un     │
-- │    workshop que sale igual o menos que las clases del mismo estudio es   │
-- │    la señal más directa de que en realidad es una clase.                 │
-- └──────────────────────────────────────────────────────────────────────────┘
select e.nombre                    as estudio,
       c.nombre                    as workshop,
       c.fecha::date               as fecha,
       c.creditos                  as creditos_workshop,
       e.creditos_max              as creditos_clase_del_estudio,
       case when c.creditos <= coalesce(e.creditos_max, 0)
            then 'SOSPECHOSO: cuesta igual o menos que una clase'
            else 'ok' end          as senal
  from public.clases c
  join public.estudios e on e.id = c.estudio_id
 where coalesce(c.tipo, 'clase') = 'workshop'
   and c.creditos <= coalesce(e.creditos_max, 0) * 1.5
 order by e.nombre, c.fecha;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 3) VOLUMEN Y PLATA: cuánto dejó de cobrar Aura por el 15%                │
-- │    Sobre reservas reales (no sobre clases publicadas). La diferencia es  │
-- │    creditos × valor_credito × (comision_aura − comision_workshop).       │
-- └──────────────────────────────────────────────────────────────────────────┘
select e.nombre                                          as estudio,
       date_trunc('month', c.fecha)::date                as mes,
       count(distinct c.id)                              as workshops,
       count(r.id)                                       as reservas,
       sum(r.creditos_usados)                            as creditos,
       round(sum(r.creditos_usados
             * coalesce(d.valor_credito, 1000)
             * (coalesce(d.comision_aura, 30) - coalesce(d.comision_workshop, 15))
             / 100.0))                                   as diferencia_vs_clase_ars
  from public.clases c
  join public.estudios e on e.id = c.estudio_id
  left join public.estudios_datos_cobro d on d.estudio_id = e.id
  left join public.reservas r
         on r.clase_id = c.id and r.estado <> 'cancelada'
 where coalesce(c.tipo, 'clase') = 'workshop'
 group by e.nombre, date_trunc('month', c.fecha), d.valor_credito,
          d.comision_aura, d.comision_workshop
 order by 2 desc, 6 desc nulls last;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 4) RITMO POR ESTUDIO: quién empezó a cargar más workshops                │
-- │    Un salto de mes a mes es la señal temprana, antes de que se note en   │
-- │    la liquidación.                                                       │
-- └──────────────────────────────────────────────────────────────────────────┘
select e.nombre                                       as estudio,
       count(*) filter (where c.fecha >= date_trunc('month', now()))                          as este_mes,
       count(*) filter (where c.fecha >= date_trunc('month', now()) - interval '1 month'
                          and c.fecha <  date_trunc('month', now()))                          as mes_pasado,
       count(*) filter (where c.fecha >= date_trunc('month', now()) - interval '3 months')    as ultimos_3_meses,
       count(*)                                                                               as historico
  from public.clases c
  join public.estudios e on e.id = c.estudio_id
 where coalesce(c.tipo, 'clase') = 'workshop'
 group by e.nombre
 order by 2 desc, 5 desc;
