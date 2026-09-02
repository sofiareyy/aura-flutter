-- =============================================================================
-- ETAPA 1 de "una reseña por reserva" — ADITIVA (2026-09-02)
-- =============================================================================
-- Decisión de producto: la reseña pasa de ser una POR ESTUDIO a una POR
-- RESERVA (modelo ClassPass). Una alumna que toma Barre con una profe y
-- Pilates con otra puede reseñar cada una por separado.
--
-- Se ata a `reserva_id` y NO a `clase_id` por dos razones medidas:
--   · en Postgres NULL no colisiona con NULL, así que un UNIQUE sobre
--     clase_id dejaría duplicar sin límite las reseñas sin clase (las 2 que
--     existen hoy son así);
--   · la reserva ES la prueba de asistencia, que es justo el permiso que hay
--     que chequear para dejar la reseña.
--
-- ⚠️ ESTA ETAPA NO TOCA EL UNIQUE VIEJO, a propósito.
-- `study_reviews_estudio_id_usuario_id_key` queda tal cual. La app instalada
-- (build 26) hace `on conflict (estudio_id, usuario_id)`: si ese índice
-- desapareciera hoy, TODAS las apps en la calle darían 42P10 al crear o
-- editar una reseña. Medido el 28/8, es el pendiente #14 del inventario.
--
-- El cambio de llave es la ETAPA 3, y va SEMANAS DESPUÉS, recién cuando los
-- estudios y las alumnas tengan la 1.0.7 con el Dart nuevo:
--     alter table public.study_reviews
--       drop constraint study_reviews_estudio_id_usuario_id_key;
--     create unique index study_reviews_reserva_uidx
--       on public.study_reviews (reserva_id) where reserva_id is not null;
-- NO adelantarla.
--
-- Las 2 reseñas que existen quedan con reserva_id null: son "reseña general
-- del estudio", se siguen mostrando y cuentan para el promedio. No se migran
-- porque sería adivinar (una de las autoras tiene 3 reservas candidatas).

alter table public.study_reviews
  add column if not exists reserva_id bigint;

-- ON DELETE SET NULL, igual que clase_id: si la reserva se borra, la reseña
-- SOBREVIVE y queda como general. Una opinión escrita no se destruye por un
-- borrado administrativo.
alter table public.study_reviews
  drop constraint if exists study_reviews_reserva_id_fkey;

alter table public.study_reviews
  add constraint study_reviews_reserva_id_fkey
  foreign key (reserva_id) references public.reservas(id) on delete set null;

-- Índice NO único: acelera "¿esta reserva ya tiene reseña?", que es la
-- pregunta que va a hacer cada fila de Mis Reservas. El único llega en la 3.
create index if not exists study_reviews_reserva_id_idx
  on public.study_reviews (reserva_id) where reserva_id is not null;

comment on column public.study_reviews.reserva_id is
  'Reserva reseñada (modelo "una reseña por asistencia", 2/9/2026). Null = '
  'reseña general del estudio: las anteriores al cambio, o las dejadas desde '
  'el perfil sin contexto de clase. El UNIQUE sobre esta columna llega en la '
  'etapa 3, tras la adopción de la 1.0.7.';
