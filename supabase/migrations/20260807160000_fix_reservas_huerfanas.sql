-- ============================================================================
-- AURA — FIX: reservas colgadas de un usuario inexistente (2026-08-07)
-- ============================================================================
--
-- Hallazgo: 36 reservas apuntaban a 1bf59530-3f4f-4d3a-b850-db0166aaf985, una
-- cuenta de prueba borrada. Verificado que NO existe ni en public.usuarios ni
-- en auth.users, así que borrarlas no destruye datos de nadie.
--
-- Causa raíz: `reservas.usuario_id` NO tenía foreign key contra usuarios. Al
-- borrar la cuenta, las reservas quedaron apuntando a un uuid inexistente.
-- `lista_espera.usuario_id` tiene exactamente el mismo agujero.
--
-- Y una bomba de tiempo aparte: la columna tenía
--     usuario_id uuid NOT NULL DEFAULT gen_random_uuid()
-- o sea que un insert que omitiera el usuario NO fallaba: inventaba un uuid al
-- azar y creaba una reserva de un usuario fantasma.
--
-- Impacto verificado ANTES de tocar nada:
--   * Plata: NINGUNO. Las 36 tenían creditos_usados = 0 y netoReserva() corta
--     en `if (cred <= 0) return 0`. No se liquidó de más.
--   * Cupo: las 30 clases futuras afectadas quedaron con lugares_disponibles
--     = 15 sobre lugares_total = 14. Están INFLADAS, no ocupadas: hay que
--     RECALCULAR, no devolver lugares.
-- ============================================================================

begin;


-- ── 1. Sacar el default que inventa usuarios ────────────────────────────────
-- Lo más urgente y lo que no depende de nada más. A partir de acá, un insert
-- sin usuario_id falla (que es lo correcto) en vez de crear un fantasma.
alter table public.reservas alter column usuario_id drop default;


-- ── 2. Guardar qué clases hay que recalcular ────────────────────────────────
-- Se arma ANTES del delete: después de borrar no habría cómo saber cuáles
-- fueron tocadas.
create temporary table _clases_a_recalcular on commit drop as
select distinct r.clase_id
  from public.reservas r
  left join public.usuarios u on u.id = r.usuario_id
 where u.id is null;


-- ── 3. Borrar las reservas colgadas ─────────────────────────────────────────
delete from public.reservas r
 using (
   select r2.id
     from public.reservas r2
     left join public.usuarios u on u.id = r2.usuario_id
    where u.id is null
 ) muertas
 where r.id = muertas.id;


-- ── 4. Mismo barrido en lista_espera ────────────────────────────────────────
-- Tiene el mismo agujero de FK. Si quedó gente colgada, sale acá.
--
-- OJO: lista_espera.usuario_id es TEXT, no uuid (usuarios.id sí es uuid), por
-- eso el cast explícito. Esa diferencia de tipo también impide ponerle la FK
-- acá: primero habría que convertir la columna a uuid, y eso va aparte porque
-- toca una tabla viva (ver nota al final del archivo).
delete from public.lista_espera le
 using (
   select le2.clase_id, le2.usuario_id
     from public.lista_espera le2
     left join public.usuarios u on u.id::text = le2.usuario_id::text
    where u.id is null
 ) muertos
 where le.clase_id = muertos.clase_id
   and le.usuario_id = muertos.usuario_id;


-- ── 5. Recalcular el cupo de las clases afectadas ───────────────────────────
-- lugares_disponibles = lugares_total - reservas activas reales, acotado a
-- [0, lugares_total]. NO se suma: las clases afectadas habían quedado con
-- disponibles (15) POR ENCIMA del total (14).
update public.clases c
   set lugares_disponibles = greatest(
         0,
         least(
           coalesce(c.lugares_total, 0),
           coalesce(c.lugares_total, 0) - coalesce(activas.n, 0)
         )
       )
  from _clases_a_recalcular t
  left join lateral (
    select count(*) as n
      from public.reservas r
     where r.clase_id = t.clase_id
       and coalesce(r.estado, '') not in ('cancelada', 'cancelada_por_estudio')
  ) activas on true
 where c.id = t.clase_id;


-- ── 6. Las foreign keys que faltaban ────────────────────────────────────────
-- ON DELETE CASCADE: si se borra un usuario, se van sus reservas y su lugar en
-- la lista de espera. Una reserva sin dueño no significa nada.
-- Va DESPUÉS de la limpieza: con filas colgadas la FK no valida.
alter table public.reservas
  drop constraint if exists reservas_usuario_id_fkey;
alter table public.reservas
  add constraint reservas_usuario_id_fkey
  foreign key (usuario_id) references public.usuarios(id) on delete cascade;

-- La FK de lista_espera queda PENDIENTE: su usuario_id es text y usuarios.id es
-- uuid, y una FK exige tipos iguales. Convertir la columna es una migración
-- aparte (hay que revisar los RPC de lista de espera que la leen/escriben).


commit;


-- ── 7. VERIFICACIÓN (solo lee) ──────────────────────────────────────────────

-- a) ¿Quedó alguna reserva o espera colgada? Tiene que dar 0 en las dos.
select 'reservas' as tabla, count(*) as colgadas
  from public.reservas r
  left join public.usuarios u on u.id = r.usuario_id
 where u.id is null
union all
select 'lista_espera', count(*)
  from public.lista_espera le
  left join public.usuarios u on u.id::text = le.usuario_id::text
 where u.id is null;

-- b) La FK nueva, con su ON DELETE. Tiene que decir CASCADE.
select con.conname,
       cl.relname as tabla,
       case con.confdeltype when 'c' then 'CASCADE' else con.confdeltype::text end as on_delete
  from pg_constraint con
  join pg_class cl on cl.oid = con.conrelid
  join pg_namespace n on n.oid = cl.relnamespace
 where n.nspname = 'public'
   and con.contype = 'f'
   and con.conname in ('reservas_usuario_id_fkey', 'lista_espera_usuario_id_fkey');

-- c) El default de usuario_id tiene que estar en null (sin gen_random_uuid).
select column_name, is_nullable, column_default
  from information_schema.columns
 where table_schema = 'public'
   and table_name = 'reservas'
   and column_name = 'usuario_id';

-- d) ¿Quedó alguna clase con el cupo descuadrado? Idealmente 0 filas.
--    Esto barre TODAS las clases futuras, no solo las que tocamos: sirve para
--    ver si el desfasaje existe en otro lado (ver nota sobre lugares_total).
select c.id, e.nombre as estudio, c.nombre as clase, c.fecha,
       c.lugares_total, c.lugares_disponibles,
       count(*) filter (
         where coalesce(r.estado, '') not in ('cancelada', 'cancelada_por_estudio')
       ) as reservas_activas
  from public.clases c
  left join public.reservas r on r.clase_id = c.id
  left join public.estudios e on e.id = c.estudio_id
 where c.fecha >= now()
 group by c.id, e.nombre, c.nombre, c.fecha, c.lugares_total, c.lugares_disponibles
having coalesce(c.lugares_disponibles, 0) <> greatest(
         0,
         coalesce(c.lugares_total, 0) - count(*) filter (
           where coalesce(r.estado, '') not in ('cancelada', 'cancelada_por_estudio')
         )
       )
 order by c.fecha;
