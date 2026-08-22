-- ============================================================================
-- AURA — Baja de codigo muerto: 4 firmas
-- ============================================================================
-- (2026-08-22) Tanda A, item 3.
--
-- `pack_credits_expiration` — MUERTA DE VERDAD
-- Barrido completo: 0 llamadores en Dart, 0 en edge functions, 0 en web, 0 en
-- funciones de la base, 0 en constraints/triggers/defaults. En los .sql del
-- repo solo aparecen su definicion y ejemplos comentados. Ya venia marcada
-- como pendiente en 20260807210000_fix_funciones_duplicadas.sql, que limpio
-- otras dos duplicadas y dejo esta anotada.
-- Tenia 3 sobrecargas de tipos ambiguos —(date,integer), (date), (text,integer)—
-- con tipos de retorno distintos. Es el patron que hace que Postgres elija la
-- equivocada si alguien la llama con literales sin castear.
--
-- `admin_update_global_credit_value` — NO estaba tan muerta
-- La nota vieja decia "0 llamadores" y era FALSO: hay un wrapper en Dart
-- (`admin_service.dart:617`, `updateGlobalCreditValue`). Lo que si es cierto es
-- que NADA invoca ese wrapper: la pantalla real (admin_config_screen.dart:103)
-- usa `setValorCreditoArs()` -> `admin_set_valor_credito_ars`. Verificado que
-- el metodo esta huerfano: aparece solo en su propia definicion, ni siquiera
-- como tear-off.
--
-- Por que se dropea IGUAL, y por que eso es MAS seguro:
--   admin_set_valor_credito_ars      escribe configuracion_global  -> SI
--   admin_update_global_credit_value escribe configuracion_global  -> NO
-- O sea que la muerta no solo era inutil: si alguien cableaba ese metodo,
-- cambiaba el valor del credito dejando `configuracion_global` desincronizada,
-- en silencio. Dropeandola ahora, ese mismo intento falla con un PGRST202
-- legible. Mejor que falle fuerte a que corrompa callado.
-- El metodo Dart huerfano queda anotado en DART_PENDIENTE_proximo_build.md.
--
-- DROP sin CASCADE a proposito: si algo dependiera, Postgres rechaza el drop
-- en vez de arrastrarlo.
--
-- VERIFICADO DESPUES DE APLICAR
--   * las 4 firmas desaparecieron
--   * admin_set_valor_credito_ars(bigint) sigue en pie, con su search_path
--   * 94 SECURITY DEFINER en public, 94 con search_path, 0 sin blindar
--   * POST /rpc/admin_update_global_credit_value -> PGRST202, falla claro
-- ============================================================================

-- Sin CASCADE a proposito: si algo dependiera de estas funciones, Postgres
-- rechaza el drop en vez de arrastrarlo en silencio.
drop function public.pack_credits_expiration(date, integer);
drop function public.pack_credits_expiration(date);
drop function public.pack_credits_expiration(text, integer);
drop function public.admin_update_global_credit_value(integer);
