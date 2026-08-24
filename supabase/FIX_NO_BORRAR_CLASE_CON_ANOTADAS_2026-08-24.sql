-- ============================================================================
-- AURA — No se puede borrar una clase con alumnas anotadas
-- ============================================================================
-- Aplicado a mano vía la Management API el 2026-08-24 (cuarta tanda del día).
-- Sin Dart ⇒ sin build. Preparación para el alta de Rock Studio.
--
-- ── EL HUECO ───────────────────────────────────────────────────────────────
-- `reservas.clase_id` es ON DELETE CASCADE: borrar una clase se lleva puestas
-- sus reservas, sin devolver créditos y sin dejar rastro.
--
-- Los tres botones del panel SÍ intentan devolver antes de borrar (llaman a
-- `cancelarClaseConDevolucion` → `estudio_cancelar_clase`). El problema es
-- cómo manejan el error:
--   · "eliminar clase suelta" (mis_clases_screen.dart:4552) — devolución y
--     borrado en el MISMO try. Falla cerrado: si la devolución falla, no
--     borra. Correcto.
--   · "eliminar horario fijo" (`_deleteFixed`, :2721) y "eliminar toda la
--     grilla" (`_eliminarGrillaCompleta`, :4624) — `try{devolver}catch(_){}`
--     y `try{borrar}catch(_){}` por separado. **Falla ABIERTO**: si la
--     devolución revienta, el error se traga y borra igual. Después el cartel
--     dice "Horario eliminado" sin mencionar créditos, porque `devueltos`
--     quedó en 0. Silencio total.
--
-- Y no era hipotético: hasta el 24/8 `estudio_cancelar_clase` moría SIEMPRE
-- con 42883 (el bug bigint→integer que arreglamos ese mismo día), así que en
-- esos dos caminos la devolución fallaba el 100% de las veces.
--
-- EVIDENCIA: el ledger no tiene **ni un solo** movimiento con source
-- 'devolucion_clase_cancelada' — ese texto lo escribe únicamente
-- `estudio_cancelar_clase`. Nunca, en toda la vida del proyecto, un borrado
-- devolvió créditos. Con 547 reservas borradas históricamente (552 ids
-- asignados, 5 filas vivas), ahí se fueron.
--
-- ── EL ARREGLO ─────────────────────────────────────────────────────────────
-- Un trigger BEFORE DELETE que rechaza el borrado si la clase tiene alumnas
-- ACTIVAS anotadas. Se eligió esto por sobre "devolver y después borrar":
--   1. Es invisible en el camino correcto. La UI ya cancela ANTES de borrar,
--      así que cuando corre el DELETE las reservas están en
--      'cancelada_por_estudio' y el trigger ni se entera. **No hay que tocar
--      Dart y nada cambia para el estudio que hace las cosas bien.**
--   2. Falla cerrado: salta exactamente cuando algo salió mal.
--   3. La alternativa haría que DELETE mueva plata en silencio, y encima sin
--      rastro (la clase y la reserva desaparecen igual). Así se obliga a pasar
--      por el camino que deja la reserva en 'cancelada_por_estudio' y que
--      además avisa a la alumna.
--
-- 'completada' queda AFUERA a propósito: si no, el estudio no podría limpiar
-- clases viejas nunca. Preservar esa historia para la facturación es otro tema
-- —romper el CASCADE— y está anotado en la Tanda E.
--
-- La guarda `current_user not in ('authenticated','anon')` exime al backoffice
-- y a los crons: dentro de un SECURITY DEFINER de postgres `current_user` pasa
-- a ser 'postgres' (comprobado midiendo), así que `admin_delete_estudio`
-- —borrar un estudio entero, que es deliberado y va con su propia
-- confirmación— sigue funcionando.
--
-- ── LAS DOS PUNTAS, midiendo efecto ────────────────────────────────────────
-- Probado como `citrabarre@gmail.com` (estudio real, NO superadmin), con una
-- alumna con 32 créditos que pagó 18 por la clase. Todo con rollback.
--
--   QUE IMPIDA                              antes              ahora
--   botón "eliminar clase suelta"     borró · saldo 32    BLOQUEADO
--   botón "eliminar horario fijo"     borró · saldo 32    BLOQUEADO
--   botón "eliminar toda la grilla"   borró · saldo 32    BLOQUEADO
--   (saldo 32 = perdió los 18 créditos)
--
--   QUE NO MOLESTE                          antes              ahora
--   cancelar y después borrar         borró · saldo 50    borró · saldo 50
--   borrar clase SIN reservas         borró               borró
--   borrar con reserva 'completada'   borró               BLOQUEADO (2da versión)
--   borrar con reserva 'cancelada'    borró               borró
--   admin_delete_estudio (backoffice) borró el estudio    borró el estudio
--   (saldo 50 = los 18 volvieron)
--
-- ── RENDIMIENTO ────────────────────────────────────────────────────────────
-- El candado corre **solo en BEFORE DELETE**. Verificado contra `pg_trigger`:
-- los otros cuatro triggers de `clases` son INSERT/UPDATE, y este es el único
-- de DELETE. No toca SELECT, así que la navegación normal no lo ve nunca.
-- Cuando sí corre, hace un único `count` sobre `reservas` filtrado por
-- `clase_id`, que tiene índice propio (`reservas_clase_id_idx`).
--
-- ── LO QUE ESTO NO CUBRE (sigue en la Tanda E) ─────────────────────────────
-- Este candado cierra el camino de todos los días: el estudio borrando clases
-- desde el panel. Quedan abiertos dos caminos que NO pasan por él:
--   · **La alumna borrando su cuenta.** `reservas.usuario_id` es CASCADE desde
--     `usuarios`, y la edge function `delete-account` corre con service_role
--     (exenta por la guarda de `current_user`) y además borra reservas a mano.
--     Medido: borrar a Male se lleva sus 2 reservas, incluida la `completada`
--     de 18 créditos facturados a Citra.
--   · **`admin_delete_estudio`**, exento a propósito.
-- Por eso romper el CASCADE **sigue siendo necesario**, aunque ahora por el
-- borrado de CUENTA y no por el de clases.
-- ============================================================================

create or replace function public.clases_bloquear_borrado_con_reservas()
returns trigger
language plpgsql
set search_path to 'public'
as $fn$
declare
  v_activas     int;
  v_completadas int;
begin
  -- Solo frenamos al PANEL. `current_user` es 'authenticated'/'anon' cuando la
  -- operacion entra por PostgREST. Dentro de un SECURITY DEFINER de postgres
  -- pasa a ser 'postgres' (comprobado), asi que `admin_delete_estudio` —el
  -- borrado deliberado de un estudio entero desde el backoffice— y los crons
  -- siguen pudiendo borrar. Mismo patron que clases_fija_precio y
  -- clases_gate_profe.
  if current_user not in ('authenticated', 'anon') then
    return old;
  end if;

  -- Estados que importan:
  --   · 'confirmada' / 'pre_confirmada' / 'presente' -> hay creditos
  --     comprometidos que devolver.
  --   · 'completada' -> ya se facturo. Borrar la clase se lleva la reserva por
  --     CASCADE y con ella la evidencia de lo que se le debe al estudio.
  -- Las 'cancelada' y 'cancelada_por_estudio' SI se pueden borrar: ahi no hay
  -- ni creditos ni facturacion en juego.
  select
    count(*) filter (where coalesce(r.estado,'') in ('confirmada','pre_confirmada','presente')),
    count(*) filter (where coalesce(r.estado,'') = 'completada')
    into v_activas, v_completadas
    from public.reservas r
   where r.clase_id = old.id;

  if v_activas > 0 then
    raise exception
      'No podés borrar esta clase porque tiene % alumna(s) anotada(s). Cancelala primero para devolverles los créditos y avisarles, después la borrás.', v_activas;
  end if;

  if v_completadas > 0 then
    raise exception
      'No podés borrar esta clase porque % alumna(s) ya la tomaron y quedó facturada. Se conserva como registro de cobro.', v_completadas;
  end if;

  return old;
end
$fn$;

drop trigger if exists trg_clases_bloquear_borrado on public.clases;
create trigger trg_clases_bloquear_borrado
  before delete on public.clases
  for each row
  execute function public.clases_bloquear_borrado_con_reservas();
