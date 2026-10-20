-- Resolver un reporte de "la clase no se dio".
-- APLICADO EN PRODUCCIÓN el 2026-10-19.
--
-- La alumna avisa (RPC `reportar_mi_clase`) y la reserva queda en
-- `en_revision`, sin liquidarse. Esto es el otro extremo: Sofía le pregunta al
-- estudio y cierra el caso. Son los dos únicos finales posibles:
--
--   SE DIO      -> la reserva vuelve a `completada` y el estudio la cobra
--                  normalmente. La alumna no fue, o se confundió.
--   NO SE DIO   -> la reserva pasa a `cancelada_por_estudio` (que no está en
--                  ninguna lista de estados liquidables, así que el estudio
--                  no la cobra) y se le devuelven los créditos a la alumna.
--
-- La devolución usa `admin_adjust_user_credits`, el mismo mecanismo con el
-- que ya se corrigieron saldos a mano. No se inventa uno nuevo.
--
-- Quién puede: sólo `is_admin()`. El estudio NO resuelve su propio caso.
--
-- Queda auditado solo: `trg_reservas_log_cambios` ya registra los cambios de
-- estado de cualquier reserva.

create or replace function public.admin_resolver_reporte(
  p_reserva_id bigint,
  p_se_dio     boolean
)
returns json
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_reserva record;
  v_devueltos int := 0;
begin
  if not public.is_admin() then
    return json_build_object('ok', false, 'error', 'no_autorizado');
  end if;

  select * into v_reserva
    from public.reservas
   where id = p_reserva_id
     for update;

  if not found then
    return json_build_object('ok', false, 'error', 'no_existe');
  end if;
  -- Sólo se resuelve lo que está en revisión: así dos clics seguidos no
  -- devuelven los créditos dos veces.
  if coalesce(v_reserva.estado, '') <> 'en_revision' then
    return json_build_object('ok', false, 'error', 'no_esta_en_revision',
                             'estado', v_reserva.estado);
  end if;

  if p_se_dio then
    update public.reservas set estado = 'completada' where id = p_reserva_id;
  else
    update public.reservas
       set estado = 'cancelada_por_estudio'
     where id = p_reserva_id;

    v_devueltos := coalesce(v_reserva.creditos_usados, 0);
    if v_devueltos > 0 then
      perform public.admin_adjust_user_credits(v_reserva.usuario_id, v_devueltos);
    end if;
  end if;

  return json_build_object('ok', true, 'se_dio', p_se_dio,
                           'creditos_devueltos', v_devueltos);
end;
$$;

revoke all on function public.admin_resolver_reporte(bigint, boolean) from public;
grant execute on function public.admin_resolver_reporte(bigint, boolean) to authenticated;
