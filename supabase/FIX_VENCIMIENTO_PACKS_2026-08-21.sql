-- =====================================================================
-- FIX: editar un pack le reseteaba el vencimiento a 90 días — 2026-08-21
-- Aplicado vía Management API y verificado con rollback + efecto (6/6).
-- Solo base, sin Dart => aplica a todos sin depender de un build nuevo.
-- =====================================================================
--
-- EL BUG
-- `AdminService.upsertPricingPack()` (admin_service.dart:662) NO manda
-- `p_vencimiento_dias`. La RPC lo tenía con `DEFAULT 90` y el UPDATE hacía
-- `vencimiento_dias = p_vencimiento_dias` sin condición. Los packs reales son
-- 30 / 45 / 45 / 60 días.
--
-- MEDIDO antes del fix (con rollback), llamando la RPC exactamente como el Dart:
--     Pack Esencial ANTES:   45 días
--     Pack Esencial DESPUÉS: 90 días   <- se rompió
--
-- ALCANCE REAL: hoy el bug NO es alcanzable desde la app.
--   upsertPricingPack : 0 llamadores fuera del service
--   listPricingPacks  : 0 llamadores
--   admin_pricing_screen.dart no toca packs (solo comisiones y valor del crédito)
-- O sea: no existe pantalla para editar packs. La trampa se dispara si se llama
-- la RPC a mano (dashboard / API) o el día que se agregue esa pantalla.
-- Se arregla igual porque es barato y queda armado.
--
-- El camino de PLANES (que sí tiene UI, admin_config_screen.dart) está limpio:
-- el Dart manda los 9 parámetros y la RPC preserva `mp_plan_id`. No se tocó.
--
-- LA CAUSA
-- `DEFAULT 90` en un upsert significa "si no me decís nada, pisá con 90". La
-- semántica correcta es "si no me decís nada, no cambies". El default
-- destructivo ES el bug; por eso el fix va del lado servidor y no del cliente:
-- aplica a todos los llamadores (app, dashboard, scripts) sin build nuevo.
--
-- DE PASO
-- Se le agrega `SET search_path to 'public'`, que le faltaba. Era uno de los
-- dos SECURITY DEFINER sin search_path que quedaban abiertos desde la auditoría
-- del 2026-08-20. Queda pendiente el otro: `ensure_referral_code`.
--
-- Nuevo default para packs CREADOS sin el parámetro: 60 días (decisión de la
-- usuaria; la columna tenía DEFAULT 90, que no se parecía a ninguno de los
-- packs reales).
-- =====================================================================

create or replace function public.admin_upsert_pricing_pack(
  p_id               integer default null,
  p_nombre           text    default '',
  p_creditos         integer default 0,
  p_precio           integer default 0,
  p_descripcion      text    default null,
  p_popular          boolean default false,
  p_activo           boolean default true,
  p_orden            integer default 0,
  p_vencimiento_dias integer default null      -- era 90 (destructivo)
)
returns void
language plpgsql
security definer
set search_path to 'public'                    -- faltaba
as $function$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  if p_id is null then
    insert into pricing_credit_packs
      (nombre, creditos, precio, descripcion, popular, activo, orden, vencimiento_dias)
    values
      (p_nombre, p_creditos, p_precio, p_descripcion, p_popular, p_activo, p_orden,
       coalesce(p_vencimiento_dias, 60));
  else
    update pricing_credit_packs set
      nombre           = p_nombre,
      creditos         = p_creditos,
      precio           = p_precio,
      descripcion      = p_descripcion,
      popular          = p_popular,
      activo           = p_activo,
      orden            = p_orden,
      -- si no lo mandan, se PRESERVA el que ya tenía
      vencimiento_dias = coalesce(p_vencimiento_dias, vencimiento_dias)
    where id = p_id;
  end if;
end
$function$;


-- =====================================================================
-- VERIFICACIÓN — 6 pruebas, con ROLLBACK, midiendo EFECTO
-- =====================================================================
-- Corrida del 2026-08-21 (post-aplicación, contra producción): 6/6.
--   1 editar SIN el parámetro          -> sigue en 45 días
--   2 editar CON p_vencimiento_dias=30 -> pasa a 30    <- control positivo
--   3 editar precio de Prueba y Full   -> conservan 30 y 60
--   4 crear pack nuevo sin el parámetro-> queda en 60
--   5 usuaria común llama la RPC       -> 'No autorizado'
--   6 estado final de los 4 packs      -> 30/45/45/60 y precios intactos
--
-- La #2 es la que hace válida a la #1: sin ella, "no cambió" también sería el
-- resultado si la función se hubiera roto y no escribiera nada.
/*
begin;
create temp table r(n int, prueba text, esperado text, resultado text, ok boolean);
grant all on r to authenticated;
select set_config('request.jwt.claims','{"sub":"<UUID DE UN SUPERADMIN>","role":"authenticated"}', true);
do $outer$
declare v_id int; v_venc int; v_prueba int; v_full int;
begin
  select id into v_id from public.pricing_credit_packs where nombre='Pack Esencial';

  set local role authenticated;
  perform public.admin_upsert_pricing_pack(
    p_id => v_id, p_nombre => 'Pack Esencial', p_creditos => 50, p_precio => 50000,
    p_descripcion => 'El pack base para usar durante el bimestre',
    p_popular => true, p_activo => true, p_orden => 2);
  reset role;
  select vencimiento_dias into v_venc from public.pricing_credit_packs where id=v_id;
  insert into r values (1,'Editar SIN p_vencimiento_dias','sigue 45', v_venc||' dias', v_venc=45);

  set local role authenticated;
  perform public.admin_upsert_pricing_pack(
    p_id => v_id, p_nombre => 'Pack Esencial', p_creditos => 50, p_precio => 50000,
    p_descripcion => 'El pack base para usar durante el bimestre',
    p_popular => true, p_activo => true, p_orden => 2, p_vencimiento_dias => 30);
  reset role;
  select vencimiento_dias into v_venc from public.pricing_credit_packs where id=v_id;
  insert into r values (2,'Editar CON p_vencimiento_dias=30 (control +)','pasa a 30', v_venc||' dias', v_venc=30);

  set local role authenticated;
  perform public.admin_upsert_pricing_pack(
    p_id => (select id from public.pricing_credit_packs where nombre='Pack Prueba'),
    p_nombre => 'Pack Prueba', p_creditos => 20, p_precio => 23000,
    p_descripcion => 'Ideal para probar Aura', p_popular => false, p_activo => true, p_orden => 1);
  perform public.admin_upsert_pricing_pack(
    p_id => (select id from public.pricing_credit_packs where nombre='Pack Full'),
    p_nombre => 'Pack Full', p_creditos => 200, p_precio => 185000,
    p_descripcion => null, p_popular => false, p_activo => true, p_orden => 4);
  reset role;
  select vencimiento_dias into v_prueba from public.pricing_credit_packs where nombre='Pack Prueba';
  select vencimiento_dias into v_full   from public.pricing_credit_packs where nombre='Pack Full';
  insert into r values (3,'Editar precio de Prueba y Full','30 y 60', v_prueba||' y '||v_full, v_prueba=30 and v_full=60);

  set local role authenticated;
  perform public.admin_upsert_pricing_pack(
    p_nombre => 'ZZ Test', p_creditos => 10, p_precio => 1000,
    p_descripcion => null, p_popular => false, p_activo => false, p_orden => 99);
  reset role;
  select vencimiento_dias into v_venc from public.pricing_credit_packs where nombre='ZZ Test';
  insert into r values (4,'Crear pack nuevo sin el parametro','60 dias', v_venc||' dias', v_venc=60);

  begin
    perform set_config('request.jwt.claims','{"sub":"<UUID DE UNA USUARIA COMUN>","role":"authenticated"}', true);
    set local role authenticated;
    perform public.admin_upsert_pricing_pack(p_id => v_id, p_nombre => 'HACK', p_creditos => 1,
      p_precio => 1, p_descripcion => null, p_popular => false, p_activo => true, p_orden => 1);
    reset role;
    insert into r values (5,'Usuaria comun llama la RPC','No autorizado','PASO (mal)', false);
  exception when others then reset role;
    insert into r values (5,'Usuaria comun llama la RPC','No autorizado','bloqueada', true);
  end;
end $outer$;
reset role;
select * from r order by n;
rollback;

-- Prueba 6, fuera de la transaccion:
-- select nombre, precio, vencimiento_dias from public.pricing_credit_packs order by orden;
*/

-- ---------------------------------------------------------------------
-- Reversión (NO recomendada: restaura el bug)
-- ---------------------------------------------------------------------
-- Cambiar el default a 90 y volver a `vencimiento_dias = p_vencimiento_dias`.

-- (fin)
