-- ============================================================================
-- AURA — Índices para que el historial no pese (2026-08-07)
-- ============================================================================
--
-- Decisión de diseño: las clases pasadas NO se borran ni se marcan con una
-- columna `archivada`. Se filtran por `fecha`, que ya es como funciona todo el
-- código hoy:
--   * app del usuario  -> clases_service / estudios_service filtran .gte(fecha, ahora)
--   * panel del estudio -> toggle "Próximas / Pasadas"
--
-- Una columna `archivada` agregaría estado duplicado (si el estudio corrige la
-- fecha de una clase, el flag quedaría mintiendo) y un cron que mantenerlo.
-- `fecha` ya es la fuente de verdad y no se desincroniza nunca.
--
-- Lo que SÍ faltaba, y es la causa real de que "pese con el tiempo", son los
-- índices. Sobre `clases` solo existía uno GIN sobre `categorias`. Y `reservas`
-- tiene la FK a clases pero Postgres NO crea índice automáticamente para las
-- foreign keys, así que contar los alumnos de una clase escaneaba la tabla
-- entera.
--
-- Esta migración NO cambia ningún dato ni ninguna estructura: solo agrega
-- índices. Es reversible con un `drop index`.

-- ── clases ──────────────────────────────────────────────────────────────────

-- El acceso más común del panel: "las clases de MI estudio en tal rango".
create index if not exists clases_estudio_fecha_idx
  on public.clases (estudio_id, fecha);

-- La grilla pública del usuario filtra por fecha sin estudio.
create index if not exists clases_fecha_idx
  on public.clases (fecha);

-- generar_clases_estudio busca duplicados por (estudio, horario_fijo, fecha).
create index if not exists clases_horario_fijo_idx
  on public.clases (horario_fijo_id)
  where horario_fijo_id is not null;


-- ── reservas ────────────────────────────────────────────────────────────────

-- Sin esto, cada "¿cuántos alumnos tiene esta clase?" era un seq scan.
create index if not exists reservas_clase_id_idx
  on public.reservas (clase_id);

-- El historial del usuario ("mis reservas") y el conteo por usuario.
create index if not exists reservas_usuario_id_idx
  on public.reservas (usuario_id);


-- ── VERIFICACIÓN (solo lee) ─────────────────────────────────────────────────

-- Índices que quedaron sobre las dos tablas.
select tablename, indexname, indexdef
  from pg_indexes
 where schemaname = 'public'
   and tablename in ('clases', 'reservas')
 order by tablename, indexname;

-- Volumen actual, para dimensionar. Si `pasadas` crece mucho y el panel se
-- pone lento pese a los índices, ahí sí conviene revisar particionado; hoy no.
select count(*) filter (where fecha <  now()) as pasadas,
       count(*) filter (where fecha >= now()) as futuras,
       count(*)                               as total
  from public.clases;
