-- ============================================================================
-- AURA — PASO 6: chequeo de regresión de precios
-- ============================================================================
-- TODO SOLO LECTURA. No cambia nada.


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 6A — ⚠️ EL MÁS IMPORTANTE: valor_credito_ars                             │
-- └──────────────────────────────────────────────────────────────────────────┘
-- La app NO tiene los precios de los packs guardados: los CALCULA como
--     creditos × valor_credito_ars × multiplicador
-- y la tabla pricing_credit_packs los tiene fijos.
--
-- La protección nueva de crear-checkout-pack exige que los dos coincidan
-- EXACTO. Si valor_credito_ars no es 1000, NADIE puede comprar un pack:
-- todos reciben "Los precios cambiaron. Actualizá la app".

select valor,
       case
         when (nullif(trim(valor), ''))::numeric = 1000
           then '✅ 1000 — la app calcula lo mismo que la tabla'
         else '🔴 NO es 1000 — las compras de packs están BLOQUEADAS'
       end as estado
  from public.configuracion_global
 where clave = 'valor_credito_ars';

-- Si no devuelve ninguna fila, la app usa su fallback de 1000 y está ok.


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 6B — Precio de la app vs precio de la tabla, pack por pack               │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Reproduce el cálculo de la app con el valor real de la base y lo compara
-- contra la tabla. Cualquier fila que no diga OK = compra bloqueada.

with v as (
  select coalesce(
           (select (nullif(trim(valor), ''))::numeric
              from public.configuracion_global
             where clave = 'valor_credito_ars'),
           1000
         ) as valor_credito
),
mult as (
  select * from (values
    ('Pack Prueba',   1.10),
    ('Pack Esencial', 1.05),
    ('Pack Popular',  1.00),
    ('Pack Full',     0.95)
  ) as t(nombre, multiplicador)
)
select p.nombre,
       p.creditos,
       round(p.creditos * v.valor_credito * m.multiplicador) as calcula_la_app,
       p.precio                                             as tiene_la_tabla,
       p.vencimiento_dias                                   as vence_en_dias,
       case
         when round(p.creditos * v.valor_credito * m.multiplicador) = p.precio
           then '✅ OK'
         else '🔴 NO COINCIDE — esta compra se rechaza'
       end as estado
  from public.pricing_credit_packs p
  join mult m on m.nombre = p.nombre
 cross join v
 where p.activo
 order by p.orden;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 6C — Los planes, y que el fallback del código coincida                   │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Tiene que dar exactamente lo mismo que AppConstants.planes:
--   Semanal 70/$70.000 · Frecuente 120/$108.000 (destacado) · Libre 160/$139.200

select orden, nombre, creditos, precio, destacado, activo, descripcion,
       case
         when (nombre, creditos, precio) in (
                ('Semanal',   70,  70000),
                ('Frecuente', 120, 108000),
                ('Libre',     160, 139200)
              ) then '✅ coincide con el fallback del código'
         else '🔴 no coincide'
       end as estado
  from public.pricing_planes
 order by orden;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 6D — ¿Quedó algo apuntando a los nombres viejos?                         │
-- └──────────────────────────────────────────────────────────────────────────┘
-- En usuarios no debería quedar nada (lo limpiamos en el PASO 2B).
-- En pagos sí puede haber historial viejo: eso es correcto y no se toca,
-- porque es lo que esa persona compró en su momento.

select 'usuarios.plan'  as donde, plan as valor, count(*) as filas
  from public.usuarios
 where plan is not null
 group by plan
union all
select 'pagos.plan_nombre', plan_nombre, count(*)
  from public.pagos
 where plan_nombre is not null
 group by plan_nombre
union all
select 'pagos.pack_nombre', pack_nombre, count(*)
  from public.pagos
 where pack_nombre is not null
 group by pack_nombre
 order by 1, 2;


-- ┌──────────────────────────────────────────────────────────────────────────┐
-- │ 6E — ¿La acreditación respeta el vencimiento que se le pasa?             │
-- └──────────────────────────────────────────────────────────────────────────┘
-- Confirma que process_approved_pack_payment usa p_expires_at en vez de
-- calcular el vencimiento por su cuenta (si lo calculara solo, todo el
-- trabajo de las vigencias 30/45/45/60 no serviría de nada).

select p.proname,
       case
         when pg_get_functiondef(p.oid) like '%p_expires_at%'
           then '✅ usa el vencimiento que le pasa la edge function'
         else '🔴 lo ignora — revisar'
       end as estado
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('process_approved_pack_payment', 'grant_user_credits')
 order by p.proname;
