-- ============================================================================
-- FIX regresión D1: los triggers de columnas sensibles rompían los RPC
-- legítimos (cambiar de estudio, editar estudio desde el backoffice, etc.)
-- ============================================================================
--
-- Los triggers usuarios_bloquear_columnas_sensibles y
-- estudios_bloquear_columnas_aura detectaban "escritura del cliente" con
-- `current_setting('role')`. Ese GUC lo setea PostgREST en 'authenticated' al
-- inicio del request y NO cambia dentro de un `security definer`. Entonces los
-- RPC legítimos (set_active_estudio, studio_add_profe, admin_upsert_estudio,
-- etc.), que son security definer y tocan esas columnas, disparaban el trigger
-- y fallaban con "No se puede cambiar el estudio desde el cliente".
--
-- Lo que SÍ cambia dentro de un security definer es `current_user`: pasa a ser
-- el owner (postgres). Un UPDATE directo del cliente vía PostgREST corre con
-- current_user = 'authenticated'/'anon'. Así que ese es el discriminador
-- correcto:
--   - current_user in (authenticated, anon)  -> escritura directa del cliente
--     => aplicar el guard (cierra la auto-escalada).
--   - cualquier otro (postgres/service_role) -> viene de un RPC autorizado o
--     del backend => permitir.
--
-- Además, los triggers pasan de SECURITY DEFINER a SECURITY INVOKER: como
-- funciones invoker, `current_user` dentro del trigger refleja el contexto que
-- ejecutó el statement disparador (postgres si vino de un definer,
-- authenticated si fue el cliente). Con DEFINER `current_user` sería siempre
-- el owner del trigger y no distinguiría el origen.
-- ============================================================================

create or replace function public.usuarios_bloquear_columnas_sensibles()
returns trigger
language plpgsql
-- SECURITY INVOKER (default): current_user refleja quién ejecutó el statement.
set search_path = public
as $$
begin
  -- Solo frenamos la escritura DIRECTA del cliente. Los RPC security definer
  -- (owned by postgres) y el service_role corren con otro current_user y pasan.
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if new.rol is distinct from old.rol then
    raise exception 'No se puede cambiar el rol desde el cliente';
  end if;

  if new.estudio_id is distinct from old.estudio_id then
    raise exception 'No se puede cambiar el estudio desde el cliente';
  end if;

  if new.creditos is distinct from old.creditos then
    raise exception 'Los creditos se ajustan solo por el ledger';
  end if;

  return new;
end;
$$;


create or replace function public.estudios_bloquear_columnas_aura()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if new.comision_aura is distinct from old.comision_aura
     or new.comision_workshop is distinct from old.comision_workshop
     or new.valor_credito is distinct from old.valor_credito
     or new.creditos_min is distinct from old.creditos_min
     or new.creditos_max is distinct from old.creditos_max
     or new.tipo_precio is distinct from old.tipo_precio
     or new.fecha_inicio_cobro is distinct from old.fecha_inicio_cobro then
    raise exception 'Comisiones y precios los define Aura desde el backoffice';
  end if;

  return new;
end;
$$;

-- Los triggers ya existen (creados en D1) y apuntan a estas funciones por
-- nombre, así que redefinir el cuerpo alcanza. Igual reafirmamos el binding
-- por si acaso.
drop trigger if exists trg_usuarios_columnas_sensibles on public.usuarios;
create trigger trg_usuarios_columnas_sensibles
  before update on public.usuarios
  for each row execute function public.usuarios_bloquear_columnas_sensibles();

drop trigger if exists trg_estudios_columnas_aura on public.estudios;
create trigger trg_estudios_columnas_aura
  before update on public.estudios
  for each row execute function public.estudios_bloquear_columnas_aura();
