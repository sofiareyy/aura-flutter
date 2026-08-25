-- ═══════════════════════════════════════════════════════════════════════════
-- FIX · consume_user_credits_detallado estaba invocable desde internet
-- 2026-08-24
--
-- EL AGUJERO
-- `consume_user_credits_detallado(p_user_id uuid, p_amount integer)` es
-- SECURITY DEFINER, NO valida quien la llama, y toma el user_id por parametro.
-- Su ACL era:
--     =X/postgres          <-- EXECUTE a PUBLIC
--     anon=X/postgres
--     authenticated=X/postgres
--
-- O sea: cualquiera con la anon key (que esta publicada dentro de la app)
-- podia vaciarle los creditos a cualquier usuaria, sin siquiera loguearse.
-- Medido antes del arreglo:
--   * como alumna real ajena: Julieta 40 cr -> 0
--   * como anon:              Male    22 cr -> 0
--   * por HTTP con la anon key: POST /rpc/consume_user_credits_detallado -> 200
--
-- POR QUE NO ALCANZA CON REVOCARLE A anon/authenticated
-- El `=X/postgres` es el grant a PUBLIC. Mientras ese este, TODO rol lo
-- hereda y revocarle a anon/authenticated no cambia nada. Hay que revocarle
-- a `public` tambien. Se midio: es la unica de las tres primitivas de
-- creditos que lo tenia.
--
-- POR QUE NO ROMPE NADA (la otra punta)
-- Sus dos unicos llamadores son SECURITY DEFINER y corren como `postgres`,
-- asi que no dependen del grant del rol que llama:
--     reservar_clase(p_clase_id bigint)
--     confirm_pre_reserva(p_reserva_id integer, p_user_id uuid, p_creditos integer)
-- El cliente Dart nunca la invoca: `reservas_service.dart:202` documenta que
-- las primitivas de credito "ya no son invocables desde el cliente" — la
-- intencion ya estaba, esta funcion se habia quedado afuera.
--
-- Queda con la MISMA ACL que sus dos hermanas, que ya estaban bien cerradas:
--     consume_user_credits  -> postgres=X, service_role=X
--     apply_reservation     -> postgres=X, service_role=X
-- ═══════════════════════════════════════════════════════════════════════════

revoke execute on function public.consume_user_credits_detallado(uuid, integer)
  from public, anon, authenticated;

-- El service_role lo conserva a proposito: es el rol del webhook de MP y de
-- las edge functions.
grant execute on function public.consume_user_credits_detallado(uuid, integer)
  to service_role;

notify pgrst, 'reload schema';
