-- ============================================================================
-- FIX: normalizar estudios.valor_credito al valor global real (1000)
-- ============================================================================
--
-- Bug reportado: al crear una clase de 18 créditos, "vos recibís" mostraba
-- $108.000 en vez de ~$18.000. Causa: 18 × 6000 = 108.000. El estudio tenía
-- `valor_credito = 6000` guardado en la base — el valor viejo de cuando había
-- un `?? 6000` hardcodeado. El valor real configurado es 1000
-- (configuracion_global.valor_credito_ars), y ValorCredito.deEstudio prefiere
-- el valor propio del estudio si está seteado, así que devolvía 6000.
--
-- Solución: normalizar el valor_credito de TODOS los estudios al valor global.
-- El modelo es un único valor de crédito (el RPC admin_set_valor_credito_ars ya
-- espeja el global a todos los estudios), así que esto solo corrige los que
-- quedaron con el 6000 viejo. Los estudios nuevos tienen valor_credito NULL y
-- caen al global igual, no necesitan tocarse.
--
-- Corre como owner (postgres): el trigger estudios_bloquear_columnas_aura solo
-- frena escrituras directas del cliente (current_user authenticated/anon), no
-- las migraciones, así que este UPDATE pasa.
-- ============================================================================

do $$
declare
  v_global int;
begin
  -- Valor global real; si no está configurado, 1000 (default de PRICING_SIMPLIFICADO).
  select nullif(btrim(valor), '')::int
    into v_global
    from public.configuracion_global
   where clave = 'valor_credito_ars'
     and nullif(btrim(valor), '') is not null
   limit 1;

  if v_global is null or v_global <= 0 then
    v_global := 1000;
  end if;

  update public.estudios
     set valor_credito = v_global
   where valor_credito is distinct from v_global;

  raise notice 'valor_credito normalizado a % en todos los estudios', v_global;
end;
$$;


-- ── VERIFICACIÓN (solo lee) ─────────────────────────────────────────────────
-- Agregado el 2026-08-13, cuando el análisis de margen destapó que esta
-- migración nunca se había corrido: Sculpt Club y Yessi Funes seguían en 6000.

-- 1) Todos los estudios tienen que quedar en el mismo valor (1000).
--    `paga_al_estudio_por_credito` es lo que te cuesta cada crédito usado ahí.
select nombre,
       valor_credito,
       comision_aura,
       fecha_inicio_cobro,
       (fecha_inicio_cobro is not null
        and fecha_inicio_cobro > current_date) as en_gracia,
       case
         when fecha_inicio_cobro is not null
          and fecha_inicio_cobro > current_date
           then coalesce(valor_credito, 1000)
         else round(coalesce(valor_credito, 1000)
                    * (100 - coalesce(comision_aura, 30)) / 100.0)
       end                                     as paga_al_estudio_por_credito
  from public.estudios
 where activo = true
 order by valor_credito desc, nombre;

-- 2) ¿Quedó alguno fuera del valor global? Tiene que dar 0 filas.
select nombre, valor_credito
  from public.estudios
 where valor_credito is not null
   and valor_credito <> (
     select nullif(btrim(valor), '')::int
       from public.configuracion_global
      where clave = 'valor_credito_ars'
   );
