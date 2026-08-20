-- ===========================================================================
-- Cerrar 2 agujeros críticos PREEXISTENTES (encontrados en la auditoría
-- integral del 2026-08-20). Solo base: no toca Dart.
-- ===========================================================================

-- ── 🔴 1. admin_upsert_pricing_pack: ponerle el guard que el nombre promete ──
-- Era SECURITY DEFINER, alcanzable por anon, y NO validaba nada.
-- `pricing_credit_packs` es la MISMA tabla que lee `crear-checkout-pack` para
-- cobrar ⇒ cualquiera con la anon key (que va en el bundle web) podía
-- reescribir el precio de un pack a $1 y comprarlo, o insertar packs nuevos.
-- Verificado explotable: se ejecutó desde anon en la auditoría.
--
-- Cuerpo y firma IDÉNTICOS al original (los 9 parámetros con sus defaults;
-- ojo con p_vencimiento_dias default 90, que el backoffice NO manda).
-- Lo único que se agrega es el guard.
create or replace function public.admin_upsert_pricing_pack(
  p_id integer default null::integer,
  p_nombre text default ''::text,
  p_creditos integer default 0,
  p_precio integer default 0,
  p_descripcion text default null::text,
  p_popular boolean default false,
  p_activo boolean default true,
  p_orden integer default 0,
  p_vencimiento_dias integer default 90)
returns void
language plpgsql
security definer
as $function$
  BEGIN
    IF NOT public.is_admin() THEN
      RAISE EXCEPTION 'No autorizado';
    END IF;

    IF p_id IS NULL THEN
      INSERT INTO pricing_credit_packs
        (nombre, creditos, precio, descripcion, popular, activo, orden, vencimiento_dias)
      VALUES
        (p_nombre, p_creditos, p_precio, p_descripcion,
         p_popular, p_activo, p_orden, p_vencimiento_dias);
    ELSE
      UPDATE pricing_credit_packs SET
        nombre           = p_nombre,
        creditos         = p_creditos,
        precio           = p_precio,
        descripcion      = p_descripcion,
        popular          = p_popular,
        activo           = p_activo,
        orden            = p_orden,
        vencimiento_dias = p_vencimiento_dias
      WHERE id = p_id;
    END IF;
  END;
  $function$;

-- Defensa en profundidad. OJO: `create or replace` PRESERVA el ACL, así que el
-- guard solo no alcanza — anon seguiría llegando a la función y sería
-- rechazado recién por la lógica. Y revocarle a `anon` es un NO-OP si PUBLIC
-- tiene el grant (anon hereda de PUBLIC): hay que revocar PUBLIC.
revoke all on function public.admin_upsert_pricing_pack(
  integer, text, integer, integer, text, boolean, boolean, integer, integer) from public, anon;
-- authenticated lo necesita: la admin entra con su sesión normal del backoffice.
grant execute on function public.admin_upsert_pricing_pack(
  integer, text, integer, integer, text, boolean, boolean, integer, integer)
  to authenticated, service_role;


-- ── 🔴 2. acreditar_creditos_corporativos: solo service_role ────────────────
-- Mintea créditos (llama a grant_user_credits en loop) y era alcanzable por
-- anon, sin ningún guard. Verificado: se ejecutó desde anon en la auditoría
-- (devolvió 0 solo porque hoy no hay empresas activas con créditos/empleado).
--
-- NO se toca el cuerpo, solo los permisos: es función de cron. La invoca la
-- edge `acreditar-creditos-corporativos`, que valida el service_role en el
-- header (fail-closed) y crea su cliente con SERVICE_ROLE_KEY.
--
-- Esto RESTAURA el candado original: supabase/EMPRESAS_CORPORATIVO.sql:207 ya
-- decía `grant execute ... to service_role`. El grant público se coló después,
-- casi seguro por un drop+create posterior (que resetea el ACL a los defaults
-- de Supabase: PUBLIC/anon/authenticated).
-- Queda igual que generar_clases_todos_estudios, que ya estaba sano.
revoke all on function public.acreditar_creditos_corporativos() from public, anon, authenticated;
grant execute on function public.acreditar_creditos_corporativos() to service_role;
