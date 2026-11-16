-- 16/11/2026 · Datos de estudios (pedido de Sofía).
-- 1) "Nuñez" (Hardcore, 69) y "Núnez" (PUR Lagree, 67) salían como dos barrios.
-- 2) Los dos BB tenían un link de Google Maps en `direccion`. La dirección
--    sale de resolver esos mismos links (maps.app.goo.gl → ?q=...).
-- Backup previo: ~/OneDrive/Aura-backups/aura-2026-11-16_1657.tar.gz
--
-- ROLLBACK (valores anteriores):
--   update estudios set barrio = 'Nuñez' where id = 69;
--   update estudios set barrio = 'Núnez' where id = 67;
--   update estudios set direccion = 'https://maps.app.goo.gl/gQVSYCteDqSoDB7GA?g_st=ic' where id = 6;
--   update estudios set direccion = 'https://maps.app.goo.gl/1tte8Y1y8mHbgzGUA?g_st=ic' where id = 7;

update public.estudios set barrio = 'Núñez' where id in (67, 69);
update public.estudios set direccion = 'Av. Álvarez Thomas 1121, C1427 CABA' where id = 6;
update public.estudios set direccion = 'Av. Olazábal 4810, C1431 CABA (timbre "BBestudio")' where id = 7;
