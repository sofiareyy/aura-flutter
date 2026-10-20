-- El mail post-clase deja de exigir check-in y de saltearse a quien ya reseñó.
-- APLICADO EN PRODUCCIÓN el 2026-10-19. Copia de lo que se corrió.
--
-- POR QUÉ: EL CANAL ESTABA MUERTO
--
-- `pedir-resenas-15min` corre cada 15 minutos desde hace meses y
-- `resena_pedida_at` estaba en **0 de 15** reservas: nunca mandó un solo
-- mail. Medido filtro por filtro, sobre las 14 reservas pasadas:
--
--   pasadas .......................... 14
--   con check-in ......................  7
--   estado presente/completada ........  7
--   usuaria no eliminada ..............  7
--   y que NO haya reseñado el estudio ..  0   <-- acá se cortaba
--
-- Las 7 eran de gente que ya había reseñado ese estudio. Ese filtro se comía
-- el 100%. No era una cuestión de criterio: era la razón por la que el canal
-- no existía.
--
-- LOS TRES CAMBIOS
--
-- 1. SE SACA el filtro de "ya reseñó este estudio". La reseña se pide una vez
--    por estudio, pero avisar que una clase no se dio es POR RESERVA: son dos
--    cosas distintas y no pueden depender una de la otra. El mail ahora
--    decide qué mostrar con `pedir_resena`, que viaja en el payload.
--
-- 2. SE SACA `checked_in_at is not null`. Que no haya check-in NO significa
--    que la clase no se dio: puede ser que el estudio se olvidó de marcar
--    presente. No se asume nada, se pregunta. Es justamente a quien no tiene
--    check-in a quien más importa preguntarle.
--
-- 3. LA VENTANA pasa de "entre 15 y 45 minutos" a "entre 15 minutos y 24 h".
--    Eran 30 minutos con un cron cada 15: si el cron se atrasaba una sola
--    vez, esa reserva perdía el mail PARA SIEMPRE, porque no hay reintento.
--    El dedup ya lo da `resena_pedida_at is null`, así que ensanchar es
--    gratis y cierra el agujero.
--
-- Volumen después del cambio: 14 reservas en total desde que existe la app.
-- No hay riesgo de avalancha.

create or replace function public.pedir_resenas_post_clase()
returns json
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_r        record;
  v_pedidas  int := 0;
  v_secret   text;
  v_url      text := 'https://hvgqpzvornlnxmsbqnwg.supabase.co/functions/v1/resena-email';
  v_anon     text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh2Z3FwenZvcm5sbnhtc2JxbndnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwNzcxMjIsImV4cCI6MjA5MDY1MzEyMn0.G5AKWyFGoL8j6IfAZV40U6TceaoQc0oVPYpepiIyDlk';
  v_ahora    timestamp := (now() at time zone 'America/Argentina/Buenos_Aires');
begin
  v_secret := (select decrypted_secret from vault.decrypted_secrets where name='notif_trigger_secret');

  for v_r in
    select r.id as reserva_id, r.usuario_id, c.id as clase_id, c.nombre as clase_nombre,
           c.estudio_id, e.nombre as estudio_nombre,
           -- Si ya reseñó ESTE estudio no se le vuelve a pedir reseña, pero
           -- el mail sale igual: lleva la pregunta de qué pasó con la clase.
           not exists (select 1 from public.study_reviews sr
                        where sr.estudio_id = c.estudio_id
                          and sr.usuario_id = r.usuario_id) as pedir_resena
      from public.reservas r
      join public.clases c on c.id = r.clase_id
      join public.estudios e on e.id = c.estudio_id
      join public.usuarios u on u.id = r.usuario_id
     where r.resena_pedida_at is null                        -- dedup
       and coalesce(r.estado,'') in ('presente','completada','ausente','confirmada')
       and u.rol is distinct from 'eliminado'                -- lápidas no
       -- La clase terminó hace entre 15 minutos y 24 horas.
       -- duracion_min es bigint y make_interval exige int: sin el cast, 42883.
       and (c.fecha + make_interval(mins => coalesce(c.duracion_min,60)::int))
             between v_ahora - interval '24 hours'
                 and v_ahora - interval '15 minutes'
  loop
    -- La campanita sólo cuando hay reseña que pedir: a quien ya reseñó, un
    -- "¿cómo estuvo?" en la campanita sería ruido.
    if v_r.pedir_resena then
      insert into public.notificaciones_usuario (usuario_id, titulo, mensaje, tipo, leida)
      values (v_r.usuario_id,
              '¿Cómo estuvo ' || coalesce(v_r.clase_nombre,'tu clase') || '?',
              'Contanos qué te pareció tu clase en ' || coalesce(v_r.estudio_nombre,'el estudio') ||
              '. Tu reseña ayuda a otras personas a descubrirlo 🧡',
              'recordatorio_resena',
              false);
    end if;

    -- Mail, fire-and-forget.
    perform net.http_post(
      url := v_url,
      headers := jsonb_build_object('Content-Type','application/json',
        'Authorization','Bearer '||v_anon,'apikey',v_anon,
        'x-notif-secret',coalesce(v_secret,'')),
      body := jsonb_build_object('kind','pedido',
        'usuario_id', v_r.usuario_id, 'estudio_id', v_r.estudio_id,
        'clase_nombre', v_r.clase_nombre,
        'reserva_id', v_r.reserva_id,
        'pedir_resena', v_r.pedir_resena)
    );

    update public.reservas set resena_pedida_at = now() where id = v_r.reserva_id;
    v_pedidas := v_pedidas + 1;
  end loop;

  return json_build_object('ok', true, 'pedidas', v_pedidas);
end;
$function$;
