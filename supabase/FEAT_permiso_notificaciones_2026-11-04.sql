-- ============================================================================
-- Saber si cada celular tiene las notificaciones prendidas (4/11/2026)
--
-- Pedido de Sofía: ver, para todos los estudios, si tienen la app pero con las
-- notificaciones apagadas, sin preguntarle a nadie. Un token registrado NO
-- alcanza: el iPhone da token aunque la persona haya tocado "No permitir", y
-- Apple descarta el push en silencio.
--
-- La app (desde el próximo build) informa el permiso al registrarse y cada vez
-- que vuelve a primer plano. Solo escribe si cambió (cuida el disco).
-- RPC nueva y aparte: no se toca registrar_dispositivo, que usan las versiones
-- viejas de la app.
--
-- Valores: 'prendido', 'apagado', 'provisorio' (iOS: llegan sin sonido al
-- centro de notificaciones), 'sin_decidir' (todavía no le preguntamos).
-- NULL = app vieja que no informa.
-- Ver: select * from metricas.permiso_push_estudios;
-- Volver atrás: ROLLBACK_permiso_notificaciones_2026-11-04.sql
-- ============================================================================

alter table public.dispositivos
  add column if not exists permiso_notificaciones text
    check (permiso_notificaciones in ('prendido','apagado','provisorio','sin_decidir')),
  add column if not exists permiso_at timestamptz;

create or replace function public.informar_permiso_notificaciones(
  p_token   text,
  p_permiso text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $fn$
begin
  if auth.uid() is null then
    raise exception 'No autorizado';
  end if;
  if p_permiso not in ('prendido','apagado','provisorio','sin_decidir') then
    raise exception 'permiso_invalido';
  end if;
  update public.dispositivos
     set permiso_notificaciones = p_permiso,
         permiso_at = now()
   where token = trim(coalesce(p_token, ''))
     and usuario_id = auth.uid()
     and permiso_notificaciones is distinct from p_permiso;
end
$fn$;

revoke all on function public.informar_permiso_notificaciones(text, text) from public, anon;
grant execute on function public.informar_permiso_notificaciones(text, text) to authenticated, service_role;

-- Para Sofía: cada admin de estudio activo, con sus celulares y el permiso.
create or replace view metricas.permiso_push_estudios as
select e.nombre                                   as estudio,
       u.email,
       d.plataforma,
       d.app_version,
       coalesce(d.permiso_notificaciones,
                case when d.id is null then 'sin_app' else 'app_vieja_no_informa' end) as permiso,
       d.permiso_at,
       d.updated_at                               as ultimo_uso_app
  from public.estudio_admins ea
  join public.estudios e on e.id = ea.estudio_id and e.activo
  join public.usuarios u on u.id = ea.usuario_id
  left join public.dispositivos d on d.usuario_id = ea.usuario_id
 where ea.rol <> 'profe'
   and not exists (select 1 from public.cuentas_internas ci where ci.email = lower(u.email))
 order by e.nombre, u.email;

revoke all on metricas.permiso_push_estudios from anon, authenticated;
