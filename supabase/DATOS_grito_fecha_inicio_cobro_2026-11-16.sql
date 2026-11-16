-- 16/11/2026 · Grito Cerámica (id 57) tenía fecha_inicio_cobro NULL, que el
-- código lee como "cobra comisión desde siempre". Decisión de Sofía: sin
-- gracia, desde la fecha de alta. El alta sale de estudio_admins (la cuenta de
-- la dueña se vinculó el 2026-09-06 23:52 UTC = 6/9 20:52 hora argentina).
-- Comisión acordada: 10% en workshops (ya estaba así en estudios_datos_cobro).
-- No hay nada que corregir hacia atrás: 0 reservas y 0 liquidaciones.
-- ROLLBACK: update public.estudios set fecha_inicio_cobro = null where id = 57;
update public.estudios set fecha_inicio_cobro = '2026-09-06' where id = 57;
