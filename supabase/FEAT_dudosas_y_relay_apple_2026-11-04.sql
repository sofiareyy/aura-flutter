-- ============================================================================
-- Cuentas dudosas aparte + liberar el relay de Apple (4/11/2026)
--
-- 1. Sofía registró somosaurapass.com y hola@somosaurapass.com en Apple
--    (Sign in with Apple for Email Communication). Las 4 direcciones
--    @privaterelay que rebotaron el 3/11 por eso salen de mail_bajas.
--    "John Apple" (csghfh6vh8@) sigue afuera igual: está en cuentas_internas.
-- 2. Tres cuentas dudosas NO se marcan como falsas (decisión de Sofía: marcar
--    mal a alguien real es peor). Quedan anotadas en cuentas_dudosas para
--    poder medir el regalo con ellas y sin ellas. No las excluye de ningún envío.
-- 3. metricas.regalo_detalle suma las columnas interna, dudosa y mail_reboto.
--    metricas.regalo_resumen deja afuera las internas (regla de siempre).
--    metricas.regalo_resumen_sin_dudosas: lo mismo sin las 3 dudosas.
-- Volver atrás: ROLLBACK_dudosas_y_relay_apple_2026-11-04.sql
-- ============================================================================

-- 1. Relay de Apple
delete from public.mail_bajas where origen = 'rebote_apple';

-- 2. Dudosas
create table if not exists public.cuentas_dudosas (
  email      text primary key,
  usuario_id uuid,
  motivo     text not null,
  created_at timestamptz not null default now()
);
alter table public.cuentas_dudosas enable row level security;
revoke all on public.cuentas_dudosas from anon, authenticated;

insert into public.cuentas_dudosas (email, usuario_id, motivo) values
  ('ahmedbalala67@gmail.com',   '05a4b11f-0c48-4e91-8667-f7e61e0d83dd', 'el nombre es un teléfono de India (+919246532703); recibió el regalo nov26'),
  ('eddymashimango6@gmail.com', '2e53fe36-2281-41d0-884d-585ab371c1f2', 'el nombre es un número (0528340936); grupo sin_regalo nov26'),
  ('noosoo123@hotmail.com',     '3c04e26c-1b54-4725-be86-9533d7e2ead4', 'nombre y mail tipo usuario genérico; recibió el regalo nov26')
on conflict (email) do nothing;

-- 3. Métricas
create or replace view metricas.regalo_detalle as
 WITH r AS (
         SELECT c_1.campana,
            c_1.usuario_id,
            count(*) FILTER (WHERE re.estado = ANY (ARRAY['confirmada'::text, 'presente'::text, 'completada'::text])) AS reservas,
            count(*) FILTER (WHERE re.estado ~~ 'cancelada%'::text) AS canceladas,
            min(re.created_at) FILTER (WHERE re.estado = ANY (ARRAY['confirmada'::text, 'presente'::text, 'completada'::text])) AS primera_reserva_at
           FROM regalo_campana c_1
             JOIN reservas re ON re.usuario_id = c_1.usuario_id AND re.created_at >= COALESCE(c_1.otorgado_at, c_1.sorteado_at)
          GROUP BY c_1.campana, c_1.usuario_id
        ), uso AS (
         SELECT c_1.campana,
            c_1.usuario_id,
            sum((e.value ->> 'taken'::text)::integer) AS creditos_regalo_usados
           FROM regalo_campana c_1
             JOIN reservas re ON re.usuario_id = c_1.usuario_id AND re.creditos_lotes IS NOT NULL AND (re.estado = ANY (ARRAY['confirmada'::text, 'presente'::text, 'completada'::text]))
             CROSS JOIN LATERAL jsonb_array_elements(re.creditos_lotes) e(value)
          WHERE c_1.lote_id IS NOT NULL AND ((e.value ->> 'id'::text)::bigint) = c_1.lote_id
          GROUP BY c_1.campana, c_1.usuario_id
        )
 SELECT c.campana,
    c.grupo,
    split_part(COALESCE(u.nombre, ''::text), ' '::text, 1) AS nombre,
    c.email,
    c.sorteado_at::date AS sorteada,
    c.salteado,
    c.otorgado_at,
    c.vence,
    COALESCE(r.reservas, 0::bigint) > 0 AS reservo,
    COALESCE(r.reservas, 0::bigint) AS reservas,
    COALESCE(r.canceladas, 0::bigint) AS canceladas,
    r.primera_reserva_at,
    COALESCE(uso.creditos_regalo_usados, 0::bigint) AS creditos_regalo_usados,
    (EXISTS ( SELECT 1
           FROM pagos p
          WHERE p.user_id = c.usuario_id AND p.status = 'approved'::text AND p.created_at >= COALESCE(c.otorgado_at, c.sorteado_at))) AS compro_despues,
    c.mail_regalo_estado,
    c.recordatorio_at IS NOT NULL AS se_le_recordo,
    c.mail_recordatorio_estado,
    mail_dado_de_baja(c.email) AS dada_de_baja,
    u.id IS NULL AS cuenta_borrada,
    (EXISTS ( SELECT 1 FROM cuentas_internas ci WHERE lower(ci.email) = lower(c.email))) AS interna,
    (EXISTS ( SELECT 1 FROM cuentas_dudosas cd WHERE cd.email = lower(c.email))) AS dudosa,
    (c.mail_regalo_estado = 'rebotó'::text) AS mail_reboto
   FROM regalo_campana c
     LEFT JOIN usuarios u ON u.id = c.usuario_id
     LEFT JOIN r ON r.campana = c.campana AND r.usuario_id = c.usuario_id
     LEFT JOIN uso ON uso.campana = c.campana AND uso.usuario_id = c.usuario_id;

create or replace view metricas.regalo_resumen as
 SELECT campana,
    grupo,
    count(*) AS personas,
    count(*) FILTER (WHERE otorgado_at IS NOT NULL) AS recibieron_regalo,
    count(*) FILTER (WHERE reservo) AS reservaron,
    round(100.0 * count(*) FILTER (WHERE reservo)::numeric / NULLIF(count(*), 0)::numeric, 1) AS pct_reservaron,
    count(*) FILTER (WHERE creditos_regalo_usados > 0) AS usaron_creditos_regalo,
    count(*) FILTER (WHERE compro_despues) AS compraron,
    count(*) FILTER (WHERE mail_regalo_estado = 'enviado'::text) AS mail_regalo_enviado,
    count(*) FILTER (WHERE se_le_recordo) AS se_les_recordo,
    count(*) FILTER (WHERE dada_de_baja) AS se_dieron_de_baja
   FROM metricas.regalo_detalle
  WHERE NOT interna
  GROUP BY campana, grupo
  ORDER BY campana, grupo;

create or replace view metricas.regalo_resumen_sin_dudosas as
 SELECT * FROM (
 SELECT campana,
    grupo,
    count(*) AS personas,
    count(*) FILTER (WHERE otorgado_at IS NOT NULL) AS recibieron_regalo,
    count(*) FILTER (WHERE reservo) AS reservaron,
    round(100.0 * count(*) FILTER (WHERE reservo)::numeric / NULLIF(count(*), 0)::numeric, 1) AS pct_reservaron,
    count(*) FILTER (WHERE creditos_regalo_usados > 0) AS usaron_creditos_regalo,
    count(*) FILTER (WHERE compro_despues) AS compraron,
    count(*) FILTER (WHERE mail_regalo_estado = 'enviado'::text) AS mail_regalo_enviado,
    count(*) FILTER (WHERE se_le_recordo) AS se_les_recordo,
    count(*) FILTER (WHERE dada_de_baja) AS se_dieron_de_baja
   FROM metricas.regalo_detalle
  WHERE NOT interna AND NOT dudosa
  GROUP BY campana, grupo) x
  ORDER BY campana, grupo;

revoke all on metricas.regalo_resumen_sin_dudosas from anon, authenticated;
