-- AURA — Auditoría previa al build: ¿existen todas las funciones que llama la
-- app? (2026-08-07). Solo LEE.
--
-- El cliente llama 68 RPC. 15 no están versionadas en el repo (se crearon desde
-- el dashboard), así que desde el código no hay forma de confirmar que existan.
-- Esta consulta las verifica todas contra la base: es el chequeo definitivo
-- para el tipo de bug "function does not exist" que veníamos encontrando.
--
-- La columna `estado` es lo único que hay que mirar: cualquier FALTA es una
-- pantalla rota esperando a que alguien la abra.

with llamadas(nombre) as (
  values
    -- Reservas y créditos (flujo de plata)
    ('reservar_clase'), ('cancelar_mi_reserva'), ('apply_reservation'),
    ('consume_user_credits'), ('grant_user_credits'),
    ('refresh_user_credit_balance'), ('admin_adjust_user_credits'),
    ('process_approved_pack_payment'), ('canjear_regalo'),
    ('acreditar_creditos_corporativos'), ('acreditar_bienvenida'),
    ('bienvenida_esta_activa'), ('admin_apagar_bienvenida'),
    ('admin_encender_bienvenida'),
    -- Lista de espera
    ('waitlist_promote_next'), ('confirm_pre_reserva'), ('release_pre_reserva'),
    ('cleanup_pre_reservas_expiradas'),
    -- Clases y grilla
    ('generar_clases_estudio'), ('generar_clases_todos_estudios'),
    ('calcular_precio_clase'), ('aplicar_pricing_a_clases_futuras'),
    ('admin_recalcular_precios_estudio'), ('admin_set_pricing_estudio'),
    ('admin_contar_clases_futuras'), ('admin_set_precio_clases_futuras'),
    ('estudio_cancelar_clase'), ('set_estudio_cierres'),
    -- Estudios y accesos
    ('admin_upsert_estudio'), ('admin_list_studios'), ('admin_delete_estudio'),
    ('admin_list_studio_members'), ('admin_list_studio_accesses'),
    ('admin_add_studio_profe'), ('admin_set_studio_access_rol'),
    ('admin_remove_studio_access'), ('admin_link_estudio_access'),
    ('studio_promote_user_to_admin'), ('studio_add_profe'),
    ('studio_list_profes'), ('remove_estudio_admin_access'),
    ('list_my_studios'), ('set_active_estudio'), ('estudio_metricas'),
    ('rol_en_estudio'), ('caller_puede_gestionar_accesos'),
    ('es_miembro_de_estudio'), ('is_admin'),
    -- Categorías
    ('admin_list_studio_categories'), ('admin_add_studio_category'),
    ('admin_rename_studio_category'), ('admin_delete_studio_category'),
    ('admin_toggle_studio_category'),
    -- Avisos y notificaciones
    ('enviar_aviso_estudio'), ('avisos_generales_restantes'),
    ('aviso_destinatarios_email'), ('notify_profes_nueva_reserva'),
    -- Backoffice / métricas / pricing global
    ('admin_dashboard_metrics'), ('admin_list_users'), ('admin_update_user'),
    ('admin_list_reservas'), ('admin_cancel_reserva'),
    ('admin_list_activity_logs'), ('admin_pricing_snapshot'),
    ('admin_list_pricing_packs'), ('admin_upsert_pricing_pack'),
    ('admin_list_pricing_plans'), ('admin_upsert_pricing_plan'),
    ('admin_set_valor_credito_ars'), ('admin_update_global_credit_value'),
    -- Empresas / referidos
    ('admin_list_empresas'), ('admin_upsert_empresa'),
    ('admin_set_empresa_activa'), ('admin_list_empresa_empleados'),
    ('apply_referral_code'), ('ensure_referral_code'),
    ('activar_referido_por_compra')
)
select l.nombre,
       case when p.proname is null then '❌ FALTA' else '✅ existe' end as estado,
       count(p.oid)                                as versiones,
       string_agg(
         pg_get_function_identity_arguments(p.oid), ' | '
       )                                           as firmas,
       bool_or(p.prosecdef)                        as security_definer
  from llamadas l
  left join pg_proc p
    on p.proname = l.nombre
   and p.pronamespace = 'public'::regnamespace
 group by l.nombre, p.proname
 order by (p.proname is null) desc, l.nombre;


-- ── Extra: funciones con MÁS DE UNA firma ──────────────────────────────────
-- Dos versiones de la misma función conviviendo es la causa clásica de
-- "funciona a veces": PostgREST elige una y el código espera la otra.
select p.proname,
       count(*) as versiones,
       string_agg(pg_get_function_identity_arguments(p.oid), '  ||  ') as firmas
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.prokind = 'f'
 group by p.proname
having count(*) > 1
 order by count(*) desc, p.proname;
