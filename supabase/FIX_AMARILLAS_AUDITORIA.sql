-- ============================================================================
-- AURA — Cerrar las 🟡 de la auditoría del 2026-08-20
-- ============================================================================
-- Aplicado a mano vía la Management API. Solo permisos: NO se tocó ningún
-- cuerpo de función, así que no hay cambio de comportamiento para los
-- llamadores legítimos. Sin Dart ⇒ sin build ni deploy.
--
-- Regla que se repitió toda la semana: `revoke ... from anon` es un NO-OP si
-- PUBLIC tiene el grant (=X/postgres), porque anon hereda de PUBLIC.
-- Hay que revocar PUBLIC explícito.
-- ============================================================================

-- ── 🟣 A service_role (procesos internos) ───────────────────────────────────

-- aviso_destinatarios_email: devolvía los EMAILS de las alumnas de un aviso y
-- era alcanzable por anon. Era la peor de las 🟡.
-- Llamador legítimo: edge `aviso-alumnos-email` (index.ts:104) con el cliente
-- `admin` creado con SERVICE_ROLE_KEY (L70). Esa edge ya valida antes que quien
-- pide sea admin del estudio (403 si no).
revoke all on function public.aviso_destinatarios_email(bigint) from public, anon, authenticated;
grant execute on function public.aviso_destinatarios_email(bigint) to service_role;

-- completar_reservas_vencidas: la dispara **pg_cron job 8** `[5 * * * *]` con
-- `user=postgres`, como `select public.completar_reservas_vencidas()` DIRECTO
-- en la base (no por HTTP con anon) ⇒ cerrarla no rompe el cron.
-- Restaura el grant que ya decía 20260722130000_fix_completar_reservas_bigint.sql:52.
revoke all on function public.completar_reservas_vencidas() from public, anon, authenticated;
grant execute on function public.completar_reservas_vencidas() to service_role;


-- ── 🔵 Internas: sin ningún llamador externo (ni Dart ni edge) ──────────────
-- Las llamadas internas desde funciones SECURITY DEFINER chequean el permiso
-- contra el owner, así que revocar PUBLIC no las afecta.

-- recalc_pack_prices  <- admin_set_valor_credito_ars (secdef)
revoke all on function public.recalc_pack_prices() from public, anon, authenticated;
grant execute on function public.recalc_pack_prices() to service_role;

-- refresh_estudio_rating  <- trigger on_study_review_changed (secdef=True)
revoke all on function public.refresh_estudio_rating(bigint) from public, anon, authenticated;
grant execute on function public.refresh_estudio_rating(bigint) to service_role;

-- vincular_usuario_a_empresa  <- trg_vincular_usuario_empresa (secdef=True),
-- admin_upsert_empresa (secdef). Es la que ENCADENABA con el minteo corporativo.
revoke all on function public.vincular_usuario_a_empresa(uuid, text) from public, anon, authenticated;
grant execute on function public.vincular_usuario_a_empresa(uuid, text) to service_role;

-- decrementar_lugares: CÓDIGO MUERTO (cero llamadores: ni Dart, ni edge, ni
-- otra función). Destructiva: bajaba cupos de cualquier clase.
-- Se REVOCA, NO se borra: revocar es reversible, borrar no. El DROP queda para
-- una limpieza aparte.
revoke all on function public.decrementar_lugares(integer) from public, anon, authenticated;


-- ⚠️ calcular_precio_clase: OJO, ESTA NO PUEDE PERDER `authenticated`.
-- Primer intento: se le revocó todo. ROMPIÓ la creación de clases:
--     ERROR 42501: permission denied for function calcular_precio_clase
--     CONTEXT: PL/pgSQL function clases_fija_precio() line 23
-- Motivo: `clases_fija_precio` y `horarios_fijos_fija_precio` son triggers
-- **NO SECURITY DEFINER** (prosecdef=false) ⇒ corren como el usuario invocante
-- (authenticated), y necesitan EXECUTE. Se corta anon, que era el hallazgo real.
revoke all on function public.calcular_precio_clase(bigint, text, integer, text) from public, anon;
grant execute on function public.calcular_precio_clase(bigint, text, integer, text) to authenticated, service_role;


-- ── 🟠 🟡 🔶 Las llama un CLIENTE autenticado ⇒ no pueden ir a service_role ──
-- Se corta anon (el hallazgo) revocando PUBLIC; queda authenticated.
-- Los guards de cuerpo (is_admin / es_miembro_de_estudio / uid propio) quedan
-- PENDIENTES: ver la nota al final del md de la auditoría.

-- 🟠 backoffice: admin_service.dart:397 y :452
revoke all on function public.admin_list_studio_categories() from public, anon;
grant execute on function public.admin_list_studio_categories() to authenticated, service_role;

-- 🟡 panel de estudio: aviso_alumnos_service.dart:65
revoke all on function public.avisos_generales_restantes(integer) from public, anon;
grant execute on function public.avisos_generales_restantes(integer) to authenticated, service_role;

-- 🔶 cliente autenticado
-- refresh_user_credit_balance: usuarios_service.dart:11 + internamente
-- grant_user_credits / consume_user_credits / admin_adjust_user_credits.
-- NO puede exigir `auth.uid() is not null`: el webhook de Mercado Pago llega
-- como service_role SIN uid y grant_user_credits la llama por dentro.
revoke all on function public.refresh_user_credit_balance(uuid) from public, anon;
grant execute on function public.refresh_user_credit_balance(uuid) to authenticated, service_role;

-- ensure_referral_code: referidos_service.dart:9
revoke all on function public.ensure_referral_code(uuid) from public, anon;
grant execute on function public.ensure_referral_code(uuid) to authenticated, service_role;

-- notify_profes_nueva_reserva: reservas_service.dart:325
revoke all on function public.notify_profes_nueva_reserva(integer, uuid) from public, anon;
grant execute on function public.notify_profes_nueva_reserva(integer, uuid) to authenticated, service_role;


-- ── 🟢 NO SE TOCAN: eran falsos positivos de la auditoría ───────────────────
-- admin_list_studio_accesses      -> wrapper de admin_list_studio_members, que
--                                    SÍ valida (auth.uid + superadmin/admin del estudio)
-- aplicar_pricing_a_clases_futuras-> wrapper de admin_recalcular_precios_estudio,
--                                    que arranca con `if not is_admin() then raise`
-- waitlist_count                  -> pública A PROPÓSITO: devuelve un integer,
--                                    nunca identidades
