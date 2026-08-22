-- ============================================================================
-- AURA — El cambio de `tipo` vuelve a disparar el cálculo de precio
-- ============================================================================
-- (2026-08-22) Arreglo 1 de 5 de la tanda de control de pricing.
--
-- EL AGUJERO
-- `clases_fija_precio` se iba temprano en un UPDATE si no habían cambiado
-- `creditos`, `fecha` ni `estudio_id`. `tipo` no estaba en esa lista, y los
-- workshops están exentos del cálculo un par de líneas más arriba. La
-- combinación daba un bypass:
--
--     1. crear la clase como tipo 'workshop' con el precio que uno quiera
--        (los workshops llevan precio libre en pesos, sin tope)
--     2. mandar un UPDATE que cambie SOLO `tipo` a 'clase'
--     3. queda una clase normal con precio arbitrario, sin repreciar
--
-- La app no lo permite (el selector de tipo solo aparece al crear), pero la
-- API sí: las policies de UPDATE del estudio sobre sus propias clases lo
-- habilitan. Verificado en una tabla temporal con la función real corriendo
-- como `authenticated`: un workshop de 9999 créditos pasado a 'clase' se
-- quedaba en 9999.
--
-- EL ARREGLO
-- Una línea: sumar `tipo` a la condición de salida temprana. La salida solo
-- deja de aplicar cuando el tipo CAMBIA, así que no toca ningún flujo real:
--   * editar nombre / instructor / cupos  -> tipo igual -> sigue sin recalcular
--   * reservar (toca lugares_disponibles) -> tipo igual -> sigue sin recalcular
-- Esa salida temprana existe justamente para no recalcular el precio en cada
-- reserva; se mantiene intacta.
--
-- LO QUE ESTE ARREGLO NO CIERRA
-- La dirección inversa (clase -> workshop) sigue abierta a propósito: el
-- workshop queda exento y después su precio se puede editar libre. Eso es el
-- arreglo 5 (tope de workshops) y la vigilancia de arbitraje de comisión
-- (15% workshop vs ~30% clase). Decisión de negocio pendiente.
--
-- `horarios_fijos` no necesita el mismo cambio: no tiene columna `tipo`.
-- ============================================================================

create or replace function public.clases_fija_precio()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
declare
  v_res json;
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  -- Workshops: el precio se carga en pesos y lo deriva Aura. No se toca.
  if coalesce(new.tipo, 'clase') = 'workshop' then
    return new;
  end if;

  -- En un UPDATE solo actuamos si cambió algo que afecta el precio. Sin esto
  -- recalcularíamos en cada reserva (que toca lugares_disponibles) al pedo.
  -- `tipo` entra en la lista para cerrar el bypass workshop -> clase.
  if tg_op = 'UPDATE'
     and new.creditos   is not distinct from old.creditos
     and new.fecha      is not distinct from old.fecha
     and new.estudio_id is not distinct from old.estudio_id
     and new.tipo       is not distinct from old.tipo then
    return new;
  end if;

  v_res := public.calcular_precio_clase(
    new.estudio_id,
    null,
    extract(isodow from new.fecha)::int,
    to_char(new.fecha, 'HH24:MI')
  );

  -- Estudio sin precio configurado: no pisamos nada (no bloqueamos la carga).
  -- OJO: esto es el arreglo 2 de la tanda — pasa a rechazar la carga.
  if coalesce((v_res ->> 'ok')::boolean, false) then
    new.creditos    := (v_res ->> 'creditos')::int;
    new.tipo_precio := v_res ->> 'tipo';
  end if;

  return new;
end;
$function$;


-- ── VERIFICACIÓN (correr aparte, no destructiva) ────────────────────────────
-- Reproduce el bypass sobre una tabla temporal y hace rollback.
--
-- begin;
--   create temp table t (like public.clases including defaults);
--   grant all on t to authenticated;
--   create trigger tt before insert or update on t
--     for each row execute function public.clases_fija_precio();
--   set local role authenticated;
--   insert into t (id, estudio_id, nombre, fecha, tipo, creditos,
--                  lugares_total, lugares_disponibles)
--   values (1, 4, 'test', '2026-09-02 19:00:00', 'workshop', 9999, 10, 10);
--   update t set tipo = 'clase' where id = 1;
--   select creditos from t where id = 1;   -- esperado: 18 (Citra Barre, fijo)
-- rollback;
