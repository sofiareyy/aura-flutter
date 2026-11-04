-- sofi.rey.2000@gmail.com deja de ser admin de Citra Barre (pedido de Sofía, 4/11/2026).
-- Las dos cosas juntas, para que no quede a medias: el vínculo (estudio_admins)
-- y el puntero viejo de usuarios (rol + estudio_id), del que cuelgan RLS y la app.
-- Citra sigue con citrabarre@ y aura.hola.app@ como admins.
-- Volver atrás:
--   insert into estudio_admins (estudio_id, usuario_id, rol) values (4, 'aae67324-abde-45d1-a157-781cef2f1bbe', 'admin_estudio');
--   update usuarios set rol = 'admin_estudio', estudio_id = 4 where id = 'aae67324-abde-45d1-a157-781cef2f1bbe';
begin;
delete from public.estudio_admins
 where usuario_id = 'aae67324-abde-45d1-a157-781cef2f1bbe' and estudio_id = 4;
update public.usuarios
   set rol = 'usuario', estudio_id = null
 where id = 'aae67324-abde-45d1-a157-781cef2f1bbe';
commit;
