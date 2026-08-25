-- ═══════════════════════════════════════════════════════════════════════════
-- FIX · farmeo de creditos corporativos (se armaba solo con la primera empresa)
-- 2026-08-24
--
-- EL AGUJERO
-- `usuarios_bloquear_columnas_sensibles` no protegia `es_corporativo` ni
-- `empresa_id`. Cualquiera podia declararse empleado de una empresa y cobrar
-- el beneficio TODOS LOS MESES: el cron `acreditar-creditos-corporativos-mensual`
-- (jobid 7, "0 3 1 * *", ACTIVO) recorre
--     usuarios where empresa_id = <empresa> and es_corporativo = true
-- y le da `creditos_por_empleado` a cada uno, sin volver a mirar el mail.
--
-- Hoy no muerde porque `empresas` esta vacia y una FK frena el empresa_id.
-- Esa FK es lo UNICO que lo tapa: el dia que entre la primera empresa, el
-- agujero se abre solo.
--
-- MEDIDO (simulando el alta de la primera empresa, 30 cr/empleado, rollback):
--   julietarey2002 (alumna real, sin relacion con la empresa)
--     no puede LEER `empresas` (RLS se lo tapa) -> pero no le hace falta:
--     adivina el id 1 y se declara empleada         -> PASA
--     cron mes 1                                     -> 40 -> 70 cr
--     tras 5 corridas                                -> 190 cr
--     5 movimientos source='corporativo', 150 creditos regalados
--
-- POR QUE NO ROMPE NADA (la otra punta)
-- Las dos columnas las escriben solo funciones SECURITY DEFINER que corren
-- como `postgres`, exentas por la guarda de `current_user`:
--     vincular_usuario_a_empresa(p_user_id, p_email)
--     trg_vincular_usuario_empresa()  -- AFTER INSERT on usuarios
-- El Dart NUNCA las escribe: `models/usuario.dart:64-65` solo las LEE para
-- mostrar el badge corporativo.
--
-- El vinculo legitimo sigue igual: se arma solo en el ALTA, por dominio de
-- mail, desde el trigger. Y como el trigger es AFTER INSERT y este guard es
-- BEFORE UPDATE, no se pisan.
--
-- ⚠️ OJO, ESTO NO CIERRA EL OTRO CAMINO: con `mailer_autoconfirm = true`
-- cualquiera se registra con un mail corporativo que no es suyo y el trigger
-- lo vincula igual. Eso es el PASO 1 de RETOMAR_ACA (verificacion de mail),
-- que sigue abierto por decision. Este guard cierra la via directa (declararse
-- empleado sin siquiera tener el mail); la via del mail falso necesita la
-- verificacion.
--
-- ⚠️ QUEDAN ESCRIBIBLES por la propia usuaria, medidas y NO tocadas aca:
--   plan, subscription_status, mp_subscription_id, renewal_date,
--   codigo_referido, codigo_referido_usado, estudio_asociado_id,
--   creditos_vencimiento, avatar_url, nombre, notifs_*
-- De esas, `plan` y `subscription_status` son las unicas con olor: se pueden
-- poner 'premium'/'authorized' a mano. Medido: NINGUNA funcion regala creditos
-- mirandolas (`process_approved_plan_payment` es SECURITY DEFINER y la dispara
-- el webhook de MP contra una fila de `pagos` real), asi que el efecto se
-- limita a mostrar un badge falso en la UI. Queda anotado, no urgente.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.usuarios_bloquear_columnas_sensibles()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
begin
  -- Solo frenamos la escritura DIRECTA del cliente. Los RPC security definer
  -- (owned by postgres) y el service_role corren con otro current_user y pasan.
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if new.rol is distinct from old.rol then
    raise exception 'No se puede cambiar el rol desde el cliente';
  end if;

  if new.estudio_id is distinct from old.estudio_id then
    raise exception 'No se puede cambiar el estudio desde el cliente';
  end if;

  if new.creditos is distinct from old.creditos then
    raise exception 'Los creditos se ajustan solo por el ledger';
  end if;

  -- 2026-08-24: el email es una COPIA de auth.users.email, no la identidad.
  -- Dejarlo escribible permitia hacerse pasar por otra cuenta ante cualquier
  -- chequeo que compare por email (era el caso de la policy de liquidaciones).
  -- El mail se cambia por Supabase Auth, que verifica el nuevo, no por aca.
  if new.email is distinct from old.email then
    raise exception 'El email no se cambia desde el cliente';
  end if;

  -- 2026-08-24: el vinculo corporativo lo decide la base en el alta, por
  -- dominio de mail (trg_vincular_usuario_empresa). Escribible desde el
  -- cliente, cualquiera se declaraba empleado y el cron mensual le regalaba
  -- los creditos del beneficio, todos los meses.
  if new.empresa_id is distinct from old.empresa_id
  or new.es_corporativo is distinct from old.es_corporativo then
    raise exception 'El vinculo con una empresa lo asigna Aura, no el cliente';
  end if;

  return new;
end;
$function$;
