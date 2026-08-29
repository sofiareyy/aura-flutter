-- 🚦 SEMÁFORO DE ADOPCIÓN DE LA APP — correr cada par de días
--
-- Cómo leerlo:
--   ✅ EN LA 26        → ya actualizó (el build 26 registra push al abrir)
--   🔴 APP VIEJA       → usa la app nativa pero no dio señal de la 26
--   🌐 sólo web        → no usa la app; la web SIEMPRE es la última, no hay nada que hacer
--
-- ⚠️ Sutileza importante: `dispositivos` sólo se llena si la persona ACEPTÓ el
-- permiso de push. Un estudio en la 26 que lo rechace seguiría figurando como
-- "app vieja". Por eso el semáforo NO sirve para declarar a alguien atrasado
-- con certeza — sirve para confirmar a quien SÍ actualizó (verde = seguro).
--
-- Cuando los 5 estén en verde, ahí sí se puede cerrar la policy de nombres
-- (`usuarios_select_alumnas_de_mis_clases`) con red.

with app as (   -- última vez que cada quien usó la APP nativa
  select s.user_id, max(s.updated_at) as ultima_app
    from auth.sessions s
   where s.user_agent ilike '%dart%'
   group by 1
), web as (     -- última vez que usó la WEB
  select s.user_id, max(s.updated_at) as ultima_web
    from auth.sessions s
   where s.user_agent ilike '%mozilla%'
   group by 1
), disp as (    -- versión que reportó al registrar push
  select d.usuario_id, max(d.app_version) as version, max(d.updated_at) as ultimo_push
    from public.dispositivos d
   group by 1
)
select e.nombre as estudio,
       u.email,
       case
         when disp.version like '%+26' or disp.version like '%+2[7-9]' then '✅ EN LA 26'
         when app.ultima_app is not null then '🔴 APP VIEJA'
         else '🌐 sólo web'
       end as estado,
       coalesce(disp.version, '—') as version_reportada,
       app.ultima_app  as ultimo_uso_app,
       web.ultima_web  as ultimo_uso_web
  from public.estudio_admins ea
  join public.estudios e on e.id = ea.estudio_id
  join public.usuarios  u on u.id = ea.usuario_id
  left join app  on app.user_id  = ea.usuario_id
  left join web  on web.user_id  = ea.usuario_id
  left join disp on disp.usuario_id = ea.usuario_id
 where ea.rol <> 'profe'
   and e.fecha_inicio_cobro is not null          -- sólo estudios reales
   and u.email <> 'aura.hola.app@gmail.com'      -- excluye la cuenta de Aura
 order by 3, 1;
