-- ============================================================================
-- AURA — Resincronizar lugares_disponibles con las reservas reales (2026-08-07)
-- ============================================================================
--
-- 63 clases futuras quedaron con lugares_disponibles MAYOR que lugares_total:
--   Yessi Funes: 43 clases con total 4 y disponibles 12
--   Citra Barre: 20 clases con total 14 y disponibles 15
--
-- No es cosmético: esas clases aceptan más reservas que el cupo real. Ninguna
-- tiene reservas activas todavía, así que corregirlas no le saca el lugar a
-- nadie.
--
-- Causa: al editar una clase, el panel manda lugares_total pero solo
-- sincroniza lugares_disponibles cuando el total es 0 (mis_clases_screen.dart,
-- payload de _editarClase). Bajar el cupo de 12 a 4 deja disponibles en 12.
-- El arreglo de raíz va en el build de Flutter; esto corrige los datos.
--
-- Solo toca clases FUTURAS: las pasadas quedan como testimonio de lo que fue.

begin;

-- El conteo va en un subquery independiente, no en un LATERAL: un
-- `update ... from lateral` no puede referenciar la tabla que se está
-- actualizando (error 42P10).
update public.clases c
   set lugares_disponibles = calc.correcto
  from (
    select cl.id,
           greatest(
             0,
             coalesce(cl.lugares_total, 0) - coalesce((
               select count(*)
                 from public.reservas r
                where r.clase_id = cl.id
                  and coalesce(r.estado, '')
                      not in ('cancelada', 'cancelada_por_estudio')
             ), 0)
           ) as correcto
      from public.clases cl
     where cl.fecha >= now()
  ) calc
 where c.id = calc.id
   and coalesce(c.lugares_disponibles, 0) <> calc.correcto;

commit;


-- ── VERIFICACIÓN (solo lee) ─────────────────────────────────────────────────
-- Tiene que dar 0 filas.
select c.id,
       e.nombre as estudio,
       c.nombre as clase,
       c.fecha,
       c.lugares_total,
       c.lugares_disponibles,
       coalesce(act.n, 0) as reservas_activas
  from public.clases c
  left join public.estudios e on e.id = c.estudio_id
  left join lateral (
    select count(*) as n
      from public.reservas r
     where r.clase_id = c.id
       and coalesce(r.estado, '') not in ('cancelada', 'cancelada_por_estudio')
  ) act on true
 where c.fecha >= now()
   and coalesce(c.lugares_disponibles, 0)
       <> greatest(0, coalesce(c.lugares_total, 0) - coalesce(act.n, 0))
 order by c.fecha;
