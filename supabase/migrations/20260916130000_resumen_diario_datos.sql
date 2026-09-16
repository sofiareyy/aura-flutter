-- ============================================================================
-- Los números del resumen diario del negocio (16/9/2026)
-- ============================================================================
--
-- Todo se calcula acá, en un solo lugar, y la edge function sólo lo maqueta.
-- Así el mail y cualquier otra vista no se pueden separar.
--
-- Regla de oro: **las cuentas internas no cuentan** (ver cuentas_internas).
-- Sin ese filtro septiembre marcaba 29 altas y las reales eran 19.
--
-- Es idempotente por día: si el cron corre dos veces, la segunda devuelve
-- `ya_enviado: true` y la function no manda nada. El número de resumen sale
-- del historial: si un día ves el #36 y nunca viste el #35, algo se rompió.
-- ============================================================================

-- `p_solo_calcular` = calcular sin registrar ni mirar el historial. Lo usa el
-- `dry_run` de la function: sin esto, probar el mail después de que el del día
-- ya salió devolvía las métricas VIEJAS guardadas — y si se agregó una métrica
-- nueva, aparecía en cero (pasó el 16/9 con el bloque de estudios).
drop function if exists public.resumen_diario_preparar();

create or replace function public.resumen_diario_preparar(
  p_solo_calcular boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hoy        date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
  v_ayer       date := v_hoy - 1;
  v_mes        text := to_char(v_hoy, 'YYYY-MM');
  v_ini_ayer   timestamptz := (v_ayer::timestamp at time zone 'America/Argentina/Buenos_Aires');
  v_fin_ayer   timestamptz := ((v_ayer + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires');
  v_ini_mes    timestamptz := (date_trunc('month', v_hoy)::timestamp at time zone 'America/Argentina/Buenos_Aires');
  v_numero     int;
  v_existente  record;
  v_m          jsonb;
  v_reportes   int := null;
begin
  -- ¿Ya salió el de hoy? (en modo cálculo no importa: se recalcula igual)
  if not p_solo_calcular then
    select * into v_existente from public.resumen_diario_envios where fecha = v_hoy;
    if found then
      return jsonb_build_object('ya_enviado', true, 'numero', v_existente.numero,
                                'fecha', v_hoy, 'metricas', v_existente.metricas);
    end if;
  end if;

  select coalesce(max(numero), 0) + 1 into v_numero from public.resumen_diario_envios;

  -- Los reportes de "la clase no se dio" todavía no existen. Va con SQL
  -- dinámico porque Postgres valida la consulta ENTERA aunque la rama no
  -- corra: un `case when to_regclass(...)` acá falla con 42P01.
  if to_regclass('public.reportes_clase_no_dada') is not null then
    execute 'select count(*) from public.reportes_clase_no_dada where estado = ''pendiente'''
       into v_reportes;
  end if;

  with cliente as (  -- las usuarias que SÍ cuentan
    select u.id, u.nombre, lower(coalesce(u.email,'')) as email, au.created_at
      from public.usuarios u
      join auth.users au on au.id = u.id
     where coalesce(u.rol, 'usuario') = 'usuario'
       and not public.es_cuenta_interna(u.email)
  )
  select jsonb_build_object(
    -- ── Movimiento ──────────────────────────────────────────────────────
    'altas_ayer', (select count(*) from cliente where created_at >= v_ini_ayer and created_at < v_fin_ayer),
    'altas_mes',  (select count(*) from cliente where created_at >= v_ini_mes),
    'reservas_ayer', (select count(*) from public.reservas r
                       where r.created_at >= v_ini_ayer and r.created_at < v_fin_ayer
                         and r.usuario_id in (select id from cliente)),
    -- De gente que nunca había reservado: es la señal de que entra gente nueva
    -- de verdad, no de que las mismas repiten.
    'reservas_ayer_de_gente_nueva', (
      select count(*) from public.reservas r
       where r.created_at >= v_ini_ayer and r.created_at < v_fin_ayer
         and r.usuario_id in (select id from cliente)
         and not exists (select 1 from public.reservas r2
                          where r2.usuario_id = r.usuario_id and r2.created_at < v_ini_ayer)),
    'packs_ayer', (select count(*) from public.pagos p
                    where p.status = 'approved' and coalesce(p.type,'') = 'pack'
                      and p.created_at >= v_ini_ayer and p.created_at < v_fin_ayer
                      and p.user_id in (select id from cliente)),
    'packs_mes', (select count(*) from public.pagos p
                   where p.status = 'approved' and coalesce(p.type,'') = 'pack'
                     and p.created_at >= v_ini_mes and p.user_id in (select id from cliente)),
    -- Las reseñas van sólo si hubo: si no, es una línea que dice 0 todos los días.
    'resenas_ayer', (select count(*) from public.study_reviews sr
                      where sr.created_at >= v_ini_ayer and sr.created_at < v_fin_ayer),

    -- ── Plata ───────────────────────────────────────────────────────────
    -- Checkouts que se abrieron y no terminaron en pago. Es el embudo real:
    -- ninguno de los pendientes tiene mp_payment_id, o sea que nadie pagó.
    'checkouts_caidos_mes', (select count(*) from public.pagos p
                              where p.status = 'pending' and coalesce(p.type,'') = 'pack'
                                and p.created_at >= v_ini_mes and p.user_id in (select id from cliente)),
    'creditos_circulacion', (select coalesce(sum(cm.amount_remaining), 0)
                               from public.creditos_movimientos cm
                              where cm.amount_remaining > 0
                                and (cm.expires_at is null or cm.expires_at >= v_hoy)
                                and cm.user_id in (select id from cliente)),
    'compraron_sin_reservar', (
      select coalesce(jsonb_agg(jsonb_build_object('nombre', c.nombre) order by c.nombre), '[]'::jsonb)
        from cliente c
       where exists (select 1 from public.creditos_movimientos cm
                      where cm.user_id = c.id and cm.source = 'pack')
         and not exists (select 1 from public.reservas r where r.usuario_id = c.id)),

    -- ── Para actuar (con nombres, si no no se puede hacer nada) ──────────
    -- La tabla de reportes todavía no existe: cuando se cree, esta línea
    -- aparece sola. `null` = la feature no está.
    'reportes_pendientes', v_reportes,
    'gracia_por_vencer', (
      select coalesce(jsonb_agg(jsonb_build_object('nombre', e.nombre, 'fecha', e.fecha_inicio_cobro)
                                order by e.fecha_inicio_cobro), '[]'::jsonb)
        from public.estudios e
       where e.activo and e.fecha_inicio_cobro between v_hoy and v_hoy + 7),
    -- ── Estudios: el panorama completo ─────────────────────────────────
    -- Sin el total, "6 sin clases" no dice si es mucho o poco.
    'estudios_total', (select count(*) from public.estudios),
    'estudios_activos', (select count(*) from public.estudios where activo),
    'estudios_con_clases', (
      select count(*) from public.estudios e
       where e.activo
         and exists (select 1 from public.clases c
                      where c.estudio_id = e.id and c.fecha > now()
                        and coalesce(c.cancelada, false) = false)),
    'estudios_sin_clases', (
      select coalesce(jsonb_agg(jsonb_build_object('nombre', e.nombre) order by e.nombre), '[]'::jsonb)
        from public.estudios e
       where e.activo
         and not exists (select 1 from public.clases c
                          where c.estudio_id = e.id and c.fecha > now()
                            and coalesce(c.cancelada, false) = false)),
    'estudios_sin_reservas_nunca', (
      select coalesce(jsonb_agg(jsonb_build_object('nombre', e.nombre) order by e.nombre), '[]'::jsonb)
        from public.estudios e
       where e.activo
         and not exists (select 1 from public.reservas r
                          join public.clases c on c.id = r.clase_id
                         where c.estudio_id = e.id))
  ) into v_m;

  if not p_solo_calcular then
    insert into public.resumen_diario_envios (numero, fecha, metricas)
    values (v_numero, v_hoy, v_m)
    on conflict (fecha) do nothing;
  end if;

  return jsonb_build_object('ya_enviado', false, 'numero', v_numero,
                            'fecha', v_hoy, 'metricas', v_m);
end;
$$;

revoke execute on function public.resumen_diario_preparar(boolean) from public, anon, authenticated;
grant execute on function public.resumen_diario_preparar(boolean) to service_role;
