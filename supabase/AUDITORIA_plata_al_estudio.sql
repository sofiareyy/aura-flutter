-- AURA — Auditoría de la cadena de plata hacia el estudio (2026-08-13).
-- Solo LEE. No modifica nada.
--
-- Cómo funciona, en criollo:
--   * Al reservar NO se escribe ninguna deuda. La reserva guarda
--     `reservas.creditos_usados` y con eso alcanza.
--   * La deuda se CALCULA cuando mirás Cobros/Liquidaciones:
--       neto = creditos_usados × valor_credito × (100 - comisión) / 100
--     con comisión 0 si el estudio está en período de gracia.
--   * Cuando marcás "pagado", recién ahí se escribe una fila en
--     `liquidaciones` con el monto CONGELADO.


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 1) La deuda de HOY, estudio por estudio (lo mismo que calcula el panel)  │
-- └──────────────────────────────────────────────────────────────────────────┘
select e.nombre                                   as estudio,
       count(*)                                   as reservas,
       sum(r.creditos_usados)                     as creditos,
       coalesce(e.valor_credito, 1000)            as valor_credito,
       sum(r.creditos_usados * coalesce(e.valor_credito, 1000)) as bruto,
       case
         when e.fecha_inicio_cobro is not null
          and e.fecha_inicio_cobro > current_date
           then 0
         else coalesce(e.comision_aura, 30)
       end                                        as comision_pct,
       round(sum(
         r.creditos_usados * coalesce(e.valor_credito, 1000)
         * (100 - case
                    when e.fecha_inicio_cobro is not null
                     and e.fecha_inicio_cobro > current_date
                      then 0
                    else coalesce(e.comision_aura, 30)
                  end) / 100.0
       ))                                         as le_debo
  from public.reservas r
  join public.clases c   on c.id = r.clase_id
  join public.estudios e on e.id = c.estudio_id
 where r.estado in ('confirmada', 'presente', 'ausente', 'completada')
 group by e.id, e.nombre, e.valor_credito, e.comision_aura, e.fecha_inicio_cobro
 order by e.nombre;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 2) Reserva por reserva, para ver el cálculo con un caso concreto         │
-- └──────────────────────────────────────────────────────────────────────────┘
select r.created_at,
       u.email                          as alumno,
       e.nombre                         as estudio,
       c.nombre                         as clase,
       r.estado,
       r.creditos_usados                as creditos,
       coalesce(e.valor_credito, 1000)  as valor_credito,
       r.creditos_usados * coalesce(e.valor_credito, 1000) as bruto,
       (e.fecha_inicio_cobro is not null
        and e.fecha_inicio_cobro > current_date) as en_gracia,
       round(
         r.creditos_usados * coalesce(e.valor_credito, 1000)
         * (100 - case
                    when e.fecha_inicio_cobro is not null
                     and e.fecha_inicio_cobro > current_date
                      then 0
                    else coalesce(e.comision_aura, 30)
                  end) / 100.0
       )                                as le_debo_por_esta
  from public.reservas r
  join public.clases c   on c.id = r.clase_id
  join public.estudios e on e.id = c.estudio_id
  left join public.usuarios u on u.id = r.usuario_id
 order by r.created_at desc
 limit 20;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 3) Liquidaciones ya registradas (montos congelados)                      │
-- └──────────────────────────────────────────────────────────────────────────┘
select l.mes, e.nombre as estudio, l.cantidad_reservas,
       l.monto_total_reservas, l.monto_a_pagar, l.estado, l.fecha_pago
  from public.liquidaciones l
  left join public.estudios e on e.id = l.estudio_id
 order by l.mes desc, e.nombre;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 4) 🔑 EL PEOR CASO: reservas que NO se le pagarían a nadie               │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Una reserva se le paga al estudio a través de clase -> estudio. Si la clase
-- fue borrada, o la reserva quedó sin usuario, la plata se pierde del cálculo.
-- Tiene que dar 0 filas.
select r.id, r.created_at, r.estado, r.creditos_usados,
       (c.id is null)  as clase_borrada,
       (u.id is null)  as usuario_borrado,
       (e.id is null)  as estudio_borrado
  from public.reservas r
  left join public.clases c   on c.id = r.clase_id
  left join public.estudios e on e.id = c.estudio_id
  left join public.usuarios u on u.id = r.usuario_id
 where r.estado in ('confirmada', 'presente', 'ausente', 'completada')
   and (c.id is null or e.id is null or u.id is null)
 order by r.created_at desc;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 5) Reservas cobradas al alumno pero con creditos_usados = 0              │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Si el alumno pagó créditos pero la reserva quedó en 0, el estudio no cobra.
-- Puede ser legítimo (alumno directo de un estudio en modo gestión), así que
-- mirá el `modo` del estudio antes de asustarte.
select e.nombre as estudio, e.modo, count(*) as reservas_en_cero
  from public.reservas r
  join public.clases c   on c.id = r.clase_id
  join public.estudios e on e.id = c.estudio_id
 where r.estado in ('confirmada', 'presente', 'ausente', 'completada')
   and coalesce(r.creditos_usados, 0) = 0
 group by e.nombre, e.modo
 order by e.nombre;
