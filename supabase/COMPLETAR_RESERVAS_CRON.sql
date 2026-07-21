-- ============================================================================
-- FIX 8 — Cron 'completar-reservas'
-- ============================================================================
--
-- PROBLEMA
-- El estado 'completada' esta definido y se LEE en varios lados
-- (reservas_service.dart:27 lo excluye de las proximas, :65 lo incluye en el
-- historial; reserva.dart:40 expone estaCompletada) pero NUNCA se ESCRIBE.
-- Las reservas quedan en 'confirmada' o 'presente' para siempre. Por eso
-- getReservasUsuario tiene que filtrar por fecha en Dart como workaround
-- (hay un comentario ahi que menciona "el cron de completar", que no existia).
--
-- SOLUCION
-- Una funcion que pasa a 'completada' las reservas cuya clase ya termino
-- (fecha + duracion_min < now()), y un pg_cron que la corre cada hora.
--
-- POR QUE SQL Y NO EDGE FUNCTION
-- No hace falta: no hay que llamar a ningun servicio externo ni mandar mails.
-- pg_cron puede invocar la funcion directo, sin round-trip HTTP, sin
-- CRON_SECRET y sin depender de que la function este deployada. Menos piezas
-- que se puedan romper.
--
-- QUE NO TOCA
--  - 'cancelada' / 'cancelada_por_estudio' -> ya son estados finales.
--  - 'ausente' -> es informativo y se liquida igual (FIX 2). Si lo pasaramos
--    a 'completada' perderiamos el dato de que no vino.
--  - 'pre_confirmada' -> la maneja el cron de lista de espera.
--  - Creditos: no se toca ninguno. Ya se consumieron al reservar.
--
-- Idempotente: se puede correr mas de una vez.
-- ============================================================================

begin;

-- ── 1. Funcion ─────────────────────────────────────────────────────────────
create or replace function public.completar_reservas_vencidas()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ahora timestamp := (
    now() at time zone 'America/Argentina/Buenos_Aires'
  );
  v_completadas int := 0;
begin
  with vencidas as (
    select r.id
      from public.reservas r
      join public.clases c on c.id = r.clase_id
     where r.estado in ('confirmada', 'presente')
       and c.fecha is not null
       -- La clase termino: inicio + duracion ya paso.
       and c.fecha
           + make_interval(
               mins => coalesce(c.duracion_min, 60)
             )
           < v_ahora
  )
  update public.reservas r
     set estado = 'completada'
    from vencidas v
   where r.id = v.id;

  get diagnostics v_completadas = row_count;

  return json_build_object(
    'completadas', v_completadas,
    'corrido_a', v_ahora
  );
end;
$$;

comment on function public.completar_reservas_vencidas is
  'Pasa a completada las reservas confirmada/presente cuya clase ya termino. La corre el cron completar-reservas cada hora. No toca creditos ni ausentes.';

grant execute on function public.completar_reservas_vencidas()
  to service_role;

-- ── 2. Cron horario ────────────────────────────────────────────────────────
create extension if not exists pg_cron;

-- cron.schedule hace UPSERT por nombre: re-correr esto no duplica el job.
-- Minuto 5 de cada hora para no pisarse con otros jobs en punto.
select cron.schedule(
  'completar-reservas',
  '5 * * * *',
  $$ select public.completar_reservas_vencidas(); $$
);

commit;

-- ── BACKFILL (opcional, correr aparte y a conciencia) ──────────────────────
-- La primera corrida va a marcar TODAS las reservas viejas de una. Si preferis
-- verlo antes de que el cron lo haga solo, corre esto:
--
--   select public.completar_reservas_vencidas();
--
-- Para ver cuantas va a tocar SIN tocarlas:
--
--   select count(*)
--     from public.reservas r
--     join public.clases c on c.id = r.clase_id
--    where r.estado in ('confirmada', 'presente')
--      and c.fecha + make_interval(mins => coalesce(c.duracion_min, 60))
--          < (now() at time zone 'America/Argentina/Buenos_Aires');

-- ── VERIFICACION ───────────────────────────────────────────────────────────
-- select jobname, schedule, active from cron.job
--  where jobname = 'completar-reservas';
--
-- select estado, count(*) from public.reservas group by estado order by 2 desc;
