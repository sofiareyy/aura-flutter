-- Reportar que la clase NO SE DIO.
-- APLICADO EN PRODUCCIÓN el 2026-10-16. Copia de lo que se corrió.
--
-- POR QUÉ
--
-- Hoy, si el estudio no da la clase, la alumna pierde los créditos y el
-- estudio cobra: el sistema no distingue "no fue" de "la clase no existió".
-- Pasó tres veces, y las tres se arreglaron a mano cancelando la reserva, que
-- era lo único que evitaba que el estudio cobrara.
--
-- El diseño está cerrado en `supabase/pendientes/RETOMAR_ACA.md` (17/9). Esto
-- es la capa de base: dos columnas y una RPC.
--
-- LAS REGLAS, tal como se decidieron
--
--  · NO devuelve créditos automáticamente. Queda en revisión y Sofía decide.
--  · La reserva pasa a `en_revision` y deja de liquidarse. `estado` no tiene
--    CHECK y las cuatro listas de estados liquidables son WHITELIST
--    (`AppConstants.estadosLiquidables` en Dart y `ESTADOS_LIQUIDABLES` en
--    TS), así que un estado nuevo queda afuera solo, sin tocar nada.
--  · Ventana de 48 h desde que TERMINA la clase.
--  · "No pude ir" no cambia el estado: sólo se registra. Sirve para saber que
--    la alumna vio la pregunta y eligió, que no es lo mismo que ignorarla.

alter table public.reservas
  add column if not exists reporte_at timestamptz,
  add column if not exists reporte_motivo text;

comment on column public.reservas.reporte_motivo is
  '"no_pude_ir" | "no_se_dio". Lo elige la alumna desde Mis Reservas dentro de las 48 h de terminada la clase. "no_se_dio" además pasa la reserva a en_revision.';

-- Índice chico para la sección del backoffice y el resumen diario: son dos
-- lecturas por día sobre "lo reportado y todavía sin resolver".
create index if not exists reservas_reporte_idx
  on public.reservas (reporte_at desc)
  where reporte_at is not null;

create or replace function public.reportar_mi_clase(
  p_reserva_id bigint,
  p_motivo     text
)
returns json
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid     uuid := auth.uid();
  v_reserva record;
  v_fin     timestamp;
  v_ahora   timestamp := (now() at time zone 'America/Argentina/Buenos_Aires');
begin
  if v_uid is null then
    return json_build_object('ok', false, 'error', 'sin_sesion');
  end if;
  if p_motivo not in ('no_pude_ir', 'no_se_dio') then
    return json_build_object('ok', false, 'error', 'motivo_invalido');
  end if;

  -- `for update` para que dos toques seguidos no dupliquen el aviso.
  select r.*, c.fecha, coalesce(c.duracion_min, 60) as dur
    into v_reserva
    from public.reservas r
    join public.clases c on c.id = r.clase_id
   where r.id = p_reserva_id
     for update of r;

  if not found then
    return json_build_object('ok', false, 'error', 'no_existe');
  end if;
  if v_reserva.usuario_id is distinct from v_uid then
    return json_build_object('ok', false, 'error', 'no_es_tuya');
  end if;
  if v_reserva.reporte_at is not null then
    return json_build_object('ok', false, 'error', 'ya_reportada');
  end if;

  -- Una reserva cancelada no se reporta: nadie perdió créditos.
  if coalesce(v_reserva.estado, '') in ('cancelada', 'cancelada_por_estudio') then
    return json_build_object('ok', false, 'error', 'cancelada');
  end if;

  v_fin := v_reserva.fecha + make_interval(mins => v_reserva.dur::int);
  if v_fin > v_ahora then
    return json_build_object('ok', false, 'error', 'todavia_no_termino');
  end if;
  if v_fin < v_ahora - interval '48 hours' then
    return json_build_object('ok', false, 'error', 'fuera_de_plazo');
  end if;

  update public.reservas
     set reporte_at     = now(),
         reporte_motivo = p_motivo,
         -- Sólo "no se dio" frena la liquidación. "No pude ir" es la alumna
         -- avisando que faltó: el estudio dio la clase y cobra.
         estado         = case when p_motivo = 'no_se_dio'
                               then 'en_revision' else estado end
   where id = p_reserva_id;

  return json_build_object('ok', true, 'motivo', p_motivo);
end;
$$;

revoke all on function public.reportar_mi_clase(bigint, text) from public;
grant execute on function public.reportar_mi_clase(bigint, text) to authenticated;

-- Lo que Sofía mira: lo reportado como "no se dio" y todavía en revisión.
-- La usa el resumen diario y la sección del backoffice, para que las dos
-- cuenten lo mismo.
create or replace view public.reportes_clase_no_dada
with (security_invoker = true) as
  select r.id            as reserva_id,
         r.reporte_at,
         r.estado,
         r.creditos_usados,
         u.nombre        as alumna,
         u.email         as alumna_email,
         c.id            as clase_id,
         c.nombre        as clase,
         c.fecha         as clase_fecha,
         e.id            as estudio_id,
         e.nombre        as estudio
    from public.reservas r
    join public.clases   c on c.id = r.clase_id
    join public.estudios e on e.id = c.estudio_id
    join public.usuarios u on u.id = r.usuario_id
   where r.reporte_motivo = 'no_se_dio'
   order by r.reporte_at desc;

grant select on public.reportes_clase_no_dada to authenticated;

-- ── Corrección del 19/10, al conectar el resumen diario ──────────────────
--
-- `resumen_diario_preparar` ya venía preparada para esto desde antes: cuenta
-- `select count(*) from public.reportes_clase_no_dada where estado = 'pendiente'`
-- y el TS del resumen ya imprime la línea en "PARA ACTUAR". Estaba esperando
-- que la vista existiera.
--
-- Pero la primera versión de la vista exponía el estado de la RESERVA
-- (`en_revision`), no el del REPORTE, así que el contador daba siempre 0. La
-- vista pasa a tener su propio ciclo de vida, que es lo que el resumen
-- espera y además es lo correcto: un reporte está pendiente mientras la
-- reserva siga en revisión, y resuelto cuando Sofía la movió (a cancelada si
-- devolvió los créditos, o de vuelta a completada si la clase sí se dio).
--
-- Va con drop+create y no con `create or replace`: Postgres no deja meter una
-- columna en el MEDIO de una vista existente.
drop view if exists public.reportes_clase_no_dada;
create view public.reportes_clase_no_dada
with (security_invoker = true) as
  select r.id            as reserva_id,
         r.reporte_at,
         case when r.estado = 'en_revision' then 'pendiente' else 'resuelto' end
                         as estado,
         r.estado        as estado_reserva,
         r.creditos_usados,
         u.nombre        as alumna,
         u.email         as alumna_email,
         c.id            as clase_id,
         c.nombre        as clase,
         c.fecha         as clase_fecha,
         e.id            as estudio_id,
         e.nombre        as estudio
    from public.reservas r
    join public.clases   c on c.id = r.clase_id
    join public.estudios e on e.id = c.estudio_id
    join public.usuarios u on u.id = r.usuario_id
   where r.reporte_motivo = 'no_se_dio'
   order by r.reporte_at desc;

grant select on public.reportes_clase_no_dada to authenticated;
