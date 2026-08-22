-- ============================================================================
-- AURA — `vigencia_dias` se mantiene sola espejada a `vencimiento_dias`
-- ============================================================================
-- (2026-08-22) Tanda A, ultimo item de datos.
--
-- CONTEXTO — esto NO es data rota, es cerrar un riesgo sobre una decision ya
-- tomada.
--
-- `pricing_credit_packs` tiene dos columnas de vencimiento. La que importa es
-- `vencimiento_dias` (la que lee el server y la que el Dart expone bajo la
-- clave `vigencia_dias`). La columna `vigencia_dias` de la TABLA quedo
-- duplicada hace tiempo y no la lee nadie: ni el Dart, ni ninguna funcion, ni
-- las edge functions. Se verifico.
--
-- Pero no es un olvido. En `PASO4_packs_precios_nuevos.sql` esta escrita la
-- decision:
--     "La columna que importa para el vencimiento es `vencimiento_dias`.
--      `vigencia_dias` no la lee nadie (quedo duplicada); la dejo en el mismo
--      valor para que no confunda mas adelante."
--
-- O sea: se eligio conservarla IGUALADA, a proposito.
--
-- EL RIESGO
-- `admin_upsert_pricing_pack` escribia solo `vencimiento_dias`. La primera
-- edicion de un pack por RPC las hacia divergir, rompiendo justamente la
-- intencion de "que no confunda". Hoy los 4 packs coinciden porque las
-- ultimas ediciones fueron por SQL a mano, no por el RPC.
--
-- EL ARREGLO
-- El upsert escribe las DOS, espejadas, en el insert y en el update. Se
-- mantienen solas y el riesgo desaparece. Se prefirio esto antes que dropear
-- la columna: dropearla revertiria una decision documentada, y eso seria una
-- decision nueva, no un arreglo.
--
-- VERIFICADO (con impersonacion de admin, porque la funcion exige is_admin)
--   * editar un pack SIN mandar vencimiento: preserva el valor en las DOS
--   * editar cambiando el vencimiento a 75: las DOS quedan en 75
--   * los 4 packs de produccion sin tocar: 30/30, 45/45, 45/45, 60/60
--
-- NO SE TOCO `creditos_por_categoria` en `configuracion_global`, que estaba en
-- la misma lista de "datos". Tambien es una retencion deliberada: la migracion
-- 20260721180000 dice "la dejamos en configuracion_global por si hay que
-- auditarla". Es archivo historico a proposito, no data rota.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.admin_upsert_pricing_pack(p_id integer DEFAULT NULL::integer, p_nombre text DEFAULT ''::text, p_creditos integer DEFAULT 0, p_precio integer DEFAULT 0, p_descripcion text DEFAULT NULL::text, p_popular boolean DEFAULT false, p_activo boolean DEFAULT true, p_orden integer DEFAULT 0, p_vencimiento_dias integer DEFAULT NULL::integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  if p_id is null then
    -- `vigencia_dias` va SIEMPRE espejada a `vencimiento_dias`. La columna
    -- quedo duplicada hace tiempo y no la lee nadie, pero se decidio conservarla
    -- con el mismo valor "para que no confunda mas adelante" (PASO4). El upsert
    -- escribia solo una de las dos, asi que la primera edicion por RPC las
    -- hacia divergir y rompia justamente esa intencion.
    insert into pricing_credit_packs
      (nombre, creditos, precio, descripcion, popular, activo, orden,
       vencimiento_dias, vigencia_dias)
    values
      (p_nombre, p_creditos, p_precio, p_descripcion, p_popular, p_activo, p_orden,
       coalesce(p_vencimiento_dias, 60), coalesce(p_vencimiento_dias, 60));
  else
    update pricing_credit_packs set
      nombre           = p_nombre,
      creditos         = p_creditos,
      precio           = p_precio,
      descripcion      = p_descripcion,
      popular          = p_popular,
      activo           = p_activo,
      orden            = p_orden,
      vencimiento_dias = coalesce(p_vencimiento_dias, vencimiento_dias),
      -- espejo, ver comentario arriba
      vigencia_dias    = coalesce(p_vencimiento_dias, vencimiento_dias)
    where id = p_id;
  end if;
end
$function$
;
