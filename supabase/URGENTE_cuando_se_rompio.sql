-- AURA — ¿Desde cuándo nadie puede reservar? (2026-08-13). Solo LEE.
--
-- Hipótesis a validar: el bug NO existe desde que se publicó la app. Empezó el
-- día que se aplicó la migración D1 (20260721210000), que revocó el EXECUTE de
-- consume_user_credits / apply_reservation y agregó el trigger del ledger.
--
-- Antes de D1 la app vieja funcionaba: la base le permitía descontar créditos
-- directo. Después de D1, el mismo código empezó a chocar.
--
-- Si la hipótesis es correcta, las reservas se cortan de golpe alrededor del
-- 21-22 de julio de 2026.


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 1) 🔑 RESERVAS POR DÍA, excluyendo cuentas de prueba                     │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Mirá si hay un corte seco alrededor del 21/07.
select date(r.created_at)                as dia,
       count(*)                          as reservas,
       count(distinct r.usuario_id)      as usuarios_distintos,
       string_agg(distinct u.email, ', ') as quienes
  from public.reservas r
  join public.usuarios u on u.id = r.usuario_id
 where u.email not ilike '%@aura.com'
 group by date(r.created_at)
 order by dia desc
 limit 40;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 2) Antes vs después de D1 (21/07/2026)                                   │
-- └──────────────────────────────────────────────────────────────────────────┘
-- La prueba directa de la hipótesis.
select case
         when r.created_at < timestamptz '2026-07-21 00:00-03'
           then 'ANTES de D1'
         else 'DESPUÉS de D1'
       end                              as periodo,
       count(*)                         as reservas,
       count(distinct r.usuario_id)     as usuarios,
       min(r.created_at)                as primera,
       max(r.created_at)                as ultima
  from public.reservas r
  join public.usuarios u on u.id = r.usuario_id
 where u.email not ilike '%@aura.com'
 group by 1
 order by 1;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 3) TODAS las reservas posteriores a D1, con detalle                      │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Si hay alguna, importa MUCHO saber de quién: si son de la web, el bug es
-- solo de iOS. Si hay de iOS, la hipótesis se cae y hay que seguir buscando.
select r.created_at,
       u.email,
       r.estado,
       r.creditos_usados,
       c.nombre  as clase,
       e.nombre  as estudio
  from public.reservas r
  join public.usuarios u on u.id = r.usuario_id
  left join public.clases c   on c.id = r.clase_id
  left join public.estudios e on e.id = c.estudio_id
 where r.created_at >= timestamptz '2026-07-21 00:00-03'
 order by r.created_at desc;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 4) Cuántos usuarios reales hay, para dimensionar el impacto              │
-- └──────────────────────────────────────────────────────────────────────────┘
select count(*) filter (where email not ilike '%@aura.com')      as usuarios_reales,
       count(*) filter (where creditos > 0
                          and email not ilike '%@aura.com')      as con_creditos_para_reservar
  from public.usuarios;
