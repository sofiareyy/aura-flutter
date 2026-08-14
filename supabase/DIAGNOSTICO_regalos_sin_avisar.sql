-- ============================================================================
-- DIAGNÓSTICO (solo lectura): regalos que el destinatario probablemente nunca
-- recibió, porque el mail de gift card no existía hasta ahora.
-- ============================================================================
--
-- Criterio: `usado = false`. Si un regalo ya fue canjeado (usado = true), el
-- destinatario sí consiguió el código (se lo pasaron a mano). Los que siguen
-- sin canjear son los candidatos a compensar / reenviar.
--
-- Cómo correrlo: abrí este archivo en TextEdit, copiá desde ACÁ (no desde el
-- chat) y pegalo en el SQL Editor de Supabase. Es un SELECT: no cambia nada.
-- ============================================================================

select
  r.id,
  r.codigo,
  r.creditos,
  r.destinatario_email,
  u.nombre        as remitente_nombre,
  au.email        as remitente_email,
  r.mensaje,
  r.created_at,
  -- ¿el destinatario ya tiene cuenta con ese email? (para saber si le llega)
  exists (
    select 1 from auth.users x
    where lower(x.email) = lower(r.destinatario_email)
  ) as destinatario_tiene_cuenta
from public.regalos r
left join public.usuarios u  on u.id = r.remitente_id
left join auth.users     au on au.id = r.remitente_id
where r.usado = false
order by r.created_at desc;

-- Total rápido, por si querés el número de una:
--   select count(*) from public.regalos where usado = false;
