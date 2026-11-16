-- Cuerpo ORIGINAL de admin_cancel_reserva (antes del 16/11/2026), para volver atrás.
CREATE OR REPLACE FUNCTION public.admin_cancel_reserva(p_reserva_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  update public.reservas
     set estado = 'cancelada'
   where id = p_reserva_id;

  perform public.log_admin_action(
    'Cancelar reserva',
    'Reserva #' || p_reserva_id,
    'reservas'
  );
end;
$function$

