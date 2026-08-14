-- ============================================================================
-- AURA — PASO 1: diagnóstico antes de limpiar y renombrar
-- ============================================================================
-- Las dos consultas son de SOLO LECTURA. No cambian nada.
-- Corré las dos y pasame los dos resultados.


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 1A — Qué cuentas tienen planes/estados de prueba                         │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Para confirmar que son todas tuyas antes de limpiarlas.

select u.email,
       u.nombre,
       u.plan,
       u.subscription_status,
       u.mp_subscription_id,
       u.renewal_date,
       u.creditos as saldo,
       (select count(*) from public.pagos p
         where p.user_id = u.id and p.type = 'plan') as pagos_de_plan
  from public.usuarios u
 where u.plan is not null
    or coalesce(u.subscription_status, 'none') <> 'none'
    or u.mp_subscription_id is not null
 order by u.email;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 1B — Cómo es la tabla pricing_planes por dentro                          │
-- └──────────────────────────────────────────────────────────────────────────┘
-- No está en las migraciones (la creaste desde el dashboard), así que
-- necesito ver las columnas exactas para escribir el UPDATE sin romperla.

select column_name,
       data_type,
       is_nullable,
       column_default
  from information_schema.columns
 where table_schema = 'public'
   and table_name   = 'pricing_planes'
 order by ordinal_position;


-- Y el contenido actual, tal cual está hoy:
select * from public.pricing_planes order by orden;
