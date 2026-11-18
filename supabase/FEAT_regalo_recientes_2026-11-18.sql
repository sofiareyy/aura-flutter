-- =============================================================================
-- Regalo de créditos a registradas recientes (campaña nov26b) — 18/11/2026
-- =============================================================================
-- Repite el regalo de noviembre (FEAT_baja_mails_y_regalo_2026-11-03.sql) con
-- otra población: registradas en los últimos 30 días. Mismo mail, misma
-- campanita, mismo recordatorio a los 10 días (cron regalo-recordatorios),
-- porque todo eso cuelga de `regalo_campana` y de regalo_otorgar.
--
-- Esta vez la métrica principal es si VOLVIERON A ABRIR la app o la web
-- después del regalo (vistas metricas.regalo_vuelta_*), no si compraron.
--
-- Este archivo crea la función de sorteo y las vistas. El sorteo y el
-- otorgamiento se corren aparte, cuando la usuaria aprueba el mail:
--   select public.regalo_sortear_recientes('nov26b', 25, 30);
--   select public.regalo_otorgar('nov26b', 20, 30);
-- =============================================================================

-- ── 1. Sorteo entre registradas recientes ──────────────────────────────────
-- Elegibles: alumnas (no estudio/profe/vinculadas), no internas, no dudosas,
-- sin baja de mails, que nunca compraron, que nunca recibieron créditos de
-- regalo (campañas, regalos de otra persona, referidos ni carga manual) y que
-- se registraron en los últimos p_dias_max días.
-- p_cantidad van al grupo 'regalo' al azar; el resto queda 'sin_regalo'
-- (control, no se las toca).
create or replace function public.regalo_sortear_recientes(
  p_campana text, p_cantidad int, p_dias_max int, p_excluir text[] default '{}')
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_total int;
begin
  if exists (select 1 from public.regalo_campana where campana = p_campana) then
    return jsonb_build_object('ok', false, 'error', 'ya_sorteada');
  end if;
  if p_cantidad is null or p_cantidad <= 0 or p_dias_max is null or p_dias_max <= 0 then
    return jsonb_build_object('ok', false, 'error', 'parametros_invalidos');
  end if;

  insert into public.regalo_campana (campana, usuario_id, email, grupo)
  select p_campana, e.id, e.email,
         case when row_number() over (order by random()) <= p_cantidad
              then 'regalo' else 'sin_regalo' end
    from (
      select u.id, lower(trim(u.email)) as email
        from public.usuarios u
        join auth.users au on au.id = u.id
       where coalesce(u.rol, 'usuario') = 'usuario'
         and coalesce(trim(u.email), '') <> ''
         and au.created_at > now() - make_interval(days => p_dias_max)
         and not public.es_cuenta_interna(u.email)
         and not exists (select 1 from public.cuentas_dudosas d
                          where d.email = lower(trim(u.email)))
         and not public.mail_dado_de_baja(u.email)
         and not public._compro_alguna_vez(u.id)
         and not public._vinculada_a_estudio(u.id)
         and not exists (select 1 from public.creditos_movimientos m
                          where m.user_id = u.id
                            and m.source in ('regalo_campana', 'regalo', 'referral', 'manual'))
         and not exists (select 1 from public.regalo_campana rc
                          where rc.usuario_id = u.id and rc.grupo = 'regalo')
         and lower(trim(u.email)) <> all (select lower(trim(x)) from unnest(coalesce(p_excluir, '{}')) x)
    ) e;
  get diagnostics v_total = row_count;

  return jsonb_build_object('ok', true, 'elegibles', v_total,
    'regalo', (select count(*) from public.regalo_campana where campana = p_campana and grupo = 'regalo'),
    'sin_regalo', (select count(*) from public.regalo_campana where campana = p_campana and grupo = 'sin_regalo'));
end;
$$;
revoke all on function public.regalo_sortear_recientes(text, int, int, text[]) from public, anon, authenticated;

-- ── 2. ¿Volvieron a abrir la app o la web? ─────────────────────────────────
-- Punto de partida: el momento del regalo. El grupo control arranca en el
-- mismo momento que su campaña (el primer otorgamiento), así las dos
-- ventanas son iguales.
-- "Abrió" = cualquier rastro posterior: se renovó o se creó su sesión de
-- Supabase, inició sesión, miró un estudio, reservó, pasó por un paso del
-- embudo o empezó un pago. Abrir sin sesión iniciada no deja rastro.
create or replace view metricas.regalo_vuelta_detalle as
with c as (
  select rc.*,
         coalesce(rc.otorgado_at,
                  (select min(x.otorgado_at) from public.regalo_campana x where x.campana = rc.campana),
                  rc.sorteado_at) as desde
    from public.regalo_campana rc
),
a as (
  select c.campana, c.usuario_id,
    greatest(
      (select max(greatest(se.updated_at, se.refreshed_at at time zone 'UTC', se.created_at))
         from auth.sessions se where se.user_id = c.usuario_id),
      (select au.last_sign_in_at from auth.users au where au.id = c.usuario_id),
      (select max(v.fecha) from public.estudio_vistas v where v.usuario_id = c.usuario_id),
      (select max(r.created_at) from public.reservas r where r.usuario_id = c.usuario_id),
      (select max(e.primera_vez_at) from public.embudo_pasos e where e.usuario_id = c.usuario_id),
      (select max(p.created_at) from public.pagos p where p.user_id = c.usuario_id)
    ) as ultima_actividad,
    (select count(*) from public.estudio_vistas v
      where v.usuario_id = c.usuario_id and v.fecha > c.desde) as estudios_vistos_despues
  from c
)
select c.campana, c.grupo, d.nombre, c.email, c.desde,
       a.ultima_actividad,
       coalesce(a.ultima_actividad > c.desde, false) as volvio,
       a.estudios_vistos_despues,
       d.reservo, d.reservas, d.creditos_regalo_usados, d.compro_despues,
       d.mail_regalo_estado, d.se_le_recordo, d.dada_de_baja,
       d.cuenta_borrada, d.interna, d.dudosa
  from c
  join a on a.campana = c.campana and a.usuario_id = c.usuario_id
  join metricas.regalo_detalle d on d.campana = c.campana and d.email = c.email;

create or replace view metricas.regalo_vuelta_resumen as
select campana, grupo,
       count(*) as personas,
       count(*) filter (where volvio) as volvieron,
       round(100.0 * count(*) filter (where volvio) / nullif(count(*), 0), 1) as pct_volvieron,
       count(*) filter (where estudios_vistos_despues > 0) as miraron_estudios,
       count(*) filter (where reservo) as reservaron,
       round(100.0 * count(*) filter (where reservo) / nullif(count(*), 0), 1) as pct_reservaron,
       count(*) filter (where creditos_regalo_usados > 0) as usaron_regalo,
       count(*) filter (where compro_despues) as compraron,
       count(*) filter (where mail_regalo_estado = 'enviado') as mail_enviado,
       count(*) filter (where se_le_recordo) as se_les_recordo,
       count(*) filter (where dada_de_baja) as se_dieron_de_baja
  from metricas.regalo_vuelta_detalle
 where not interna
 group by campana, grupo
 order by campana, grupo;

create or replace view metricas.regalo_vuelta_resumen_sin_dudosas as
select campana, grupo,
       count(*) as personas,
       count(*) filter (where volvio) as volvieron,
       round(100.0 * count(*) filter (where volvio) / nullif(count(*), 0), 1) as pct_volvieron,
       count(*) filter (where reservo) as reservaron,
       count(*) filter (where compro_despues) as compraron
  from metricas.regalo_vuelta_detalle
 where not interna and not dudosa
 group by campana, grupo
 order by campana, grupo;

-- Mismo criterio que las vistas de metricas existentes: no las ve la API.
revoke all on metricas.regalo_vuelta_detalle, metricas.regalo_vuelta_resumen,
              metricas.regalo_vuelta_resumen_sin_dudosas from anon, authenticated;
