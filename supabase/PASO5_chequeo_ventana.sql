-- ============================================================================
-- AURA — PASO 5: ¿alguien compró durante la ventana?
-- ============================================================================
-- SOLO LECTURA.
--
-- La ventana: entre que corriste el PASO 4 (tabla con precios nuevos) y las
-- 16:59 de hoy (deploy de las edge functions con el chequeo de precio).
-- En ese rato, la app mostraba el precio viejo y el checkout cobraba el nuevo.
--
-- Miro las últimas 6 horas para tener margen de sobra.

select p.created_at,
       u.email,
       p.type,
       p.status,
       p.pack_nombre,
       p.plan_nombre,
       p.creditos,
       p.amount           as se_cobro,
       p.credits_granted_at,
       -- Lo que la app le habría mostrado ANTES del cambio de precios:
       case p.pack_nombre
         when 'Pack Prueba'   then 22000
         when 'Pack Esencial' then 50000
         when 'Pack Popular'  then 95000
         when 'Pack Full'     then 180000
       end                as mostraba_la_app_vieja,
       case
         when p.type <> 'pack' then '—'
         when p.amount = case p.pack_nombre
                           when 'Pack Prueba'   then 22000
                           when 'Pack Esencial' then 50000
                           when 'Pack Popular'  then 95000
                           when 'Pack Full'     then 180000
                         end then 'ok, precio viejo'
         when p.amount = case p.pack_nombre
                           when 'Pack Prueba'   then 22000
                           when 'Pack Esencial' then 52500
                           when 'Pack Popular'  then 100000
                           when 'Pack Full'     then 190000
                         end then 'precio nuevo'
         else 'revisar'
       end                as diagnostico
  from public.pagos p
  left join public.usuarios u on u.id = p.user_id
 where p.created_at >= now() - interval '6 hours'
 order by p.created_at desc;


-- Si devuelve 0 filas: nadie compró nada, ventana limpia, se puede pushear.
--
-- Si aparece alguna fila 'pack' con status 'approved' y diagnostico
-- 'precio nuevo', esa persona pagó de más: la diferencia es
-- $2.500 (Esencial), $5.000 (Popular) o $10.000 (Full).
