-- =============================================================================
-- Un estudio inactivo no se muestra en la app (2026-08-30)
-- =============================================================================
-- El bug (medido el 30/8): el botón "inactivo" del backoffice SÍ guarda
-- (`admin_upsert_estudio` escribe `activo`), pero NADIE mira ese campo:
--   · `estudios` tenía la policy "todos pueden ver estudios" USING (true)
--   · `clases`   tenía "Lectura publica clases"            USING (true)
--   · getEstudios()/getProximasClases() no filtran, y el modelo Estudio de
--     Dart ni siquiera parsea `activo`.
-- Resultado: un estudio desactivado seguía en Inicio, Explorar y Mapa, y sus
-- clases seguían listándose y siendo reservables. Publicidad gratis.
--
-- Caso de uso (confirmado por la usuaria): "inactivo" NO es una baja, es
-- "no mostrar en Aura" — estudios de prueba (Hot Clic) o sin clases cargadas.
--
-- Se arregla EN LA BASE a propósito: así vale para todas las apps, incluidas
-- las ya instaladas, sin esperar un build. Un filtro en Dart sólo protegería
-- a quien actualice.
--
-- Las dos tablas, porque las clases se leen de `clases` y no de `estudios`:
-- esconder sólo el estudio dejaba las clases huérfanas listándose sueltas
-- (medido con Citra: 184 clases seguían apareciendo).
--
-- Quién SIGUE viendo un estudio inactivo y sus clases:
--   · el propio estudio (su panel tiene que funcionar para poder cargar), y
--   · Aura (superadmin), por `es_miembro_de_estudio`, que ya cubre admin_users.
-- ⚠️ Una alumna con una reserva viva en un estudio que se desactiva dejaría de
-- ver esa clase. Hoy no aplica: la usuaria verifica que no haya reservas antes
-- de desactivar. Si algún día se desactiva un estudio con reservas, sumarle a
-- la policy de `clases` un `or exists (select 1 from reservas ...)`.

-- 1) El estudio inactivo no se lista.
drop policy if exists "todos pueden ver estudios" on public.estudios;

create policy "estudios visibles: activos, o los tuyos"
  on public.estudios for select
  using (
    coalesce(activo, true)
    or public.es_miembro_de_estudio(id)
  );

-- 2) Y sus clases tampoco (si no, quedan huérfanas en Explorar/Inicio).
drop policy if exists "Lectura publica clases" on public.clases;

create policy "clases visibles: las de estudios activos, o las tuyas"
  on public.clases for select
  using (
    exists (
      select 1 from public.estudios e
       where e.id = clases.estudio_id
         and coalesce(e.activo, true)
    )
    or public.es_miembro_de_estudio(estudio_id)
  );

-- 3) ⚠️ Encontrado al verificar: `anon` no tenía EXECUTE sobre
-- es_miembro_de_estudio (las policies que ya la usaban —horarios_fijos,
-- estudio_servicios_precio— son sólo para authenticated, así que nunca había
-- hecho falta). Sin este grant, el MODO VISITA (pre-login) se caía con 42501
-- al leer estudios o clases. Para anon la función siempre da false
-- (auth.uid() es null), que es exactamente lo que corresponde.
grant execute on function public.es_miembro_de_estudio(bigint) to anon;
