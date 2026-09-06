-- El guard del "pagado" de las liquidaciones (6/9/2026).
--
-- LO QUE PASÓ. Con la primera facturación real (Citra, agosto), el estudio vio
-- "Pagado" cuando Aura todavía no había pagado. Medido: en `liquidaciones` no
-- había NINGUNA fila de Citra. El "Pagado" salía de la pantalla vieja de la
-- app del teléfono (1.0.6), que inventaba el estado con la regla "si el mes ya
-- no es el actual, decí Pagado". La web ya estaba arreglada desde el 2/9.
--
-- LO QUE ESTO GARANTIZA. Que en la BASE nunca exista una liquidación pagada
-- que no sea un pago real. La pantalla puede mentir hasta que se actualice;
-- la base no.
--
--   1. `estado = 'pagado'` exige `fecha_pago`. Sin fecha no hay pago.
--   2. Un pago no se deshace: pagado no vuelve a pendiente, y no se le cambia
--      el estudio, el mes ni la plata. Lo único editable es la nota.
--   3. El estado sólo puede ser 'pendiente' o 'pagado'. Hoy no había CHECK y
--      cualquier string entraba.
--
-- NO cambia quién puede escribir (sigue siendo sólo admin por RLS) ni el
-- sellado de comisión (es otro trigger, que corre después de éste).

begin;

alter table public.liquidaciones
  drop constraint if exists liquidaciones_estado_check;
alter table public.liquidaciones
  add constraint liquidaciones_estado_check
  check (estado in ('pendiente', 'pagado'));

alter table public.liquidaciones
  drop constraint if exists liquidaciones_pagado_con_fecha;
alter table public.liquidaciones
  add constraint liquidaciones_pagado_con_fecha
  check (estado <> 'pagado' or fecha_pago is not null);

create or replace function public.liquidaciones_guard_pagado()
returns trigger
language plpgsql
as $$
begin
  -- Un pago hecho no se deshace desde ninguna pantalla. Si de verdad hay que
  -- corregirlo, es una operación de base a mano, con registro.
  if tg_op = 'UPDATE' and old.estado = 'pagado' then
    if new.estado <> 'pagado' then
      raise exception 'Una liquidación pagada no vuelve a pendiente (id %)', old.id
        using errcode = 'check_violation';
    end if;
    if new.estudio_id <> old.estudio_id or new.mes <> old.mes then
      raise exception 'Una liquidación pagada no cambia de estudio ni de mes (id %)', old.id
        using errcode = 'check_violation';
    end if;
    if new.monto_a_pagar <> old.monto_a_pagar
       or new.monto_total_reservas <> old.monto_total_reservas
       or new.cantidad_reservas <> old.cantidad_reservas then
      raise exception 'Una liquidación pagada no cambia de monto (id %)', old.id
        using errcode = 'check_violation';
    end if;
    -- La fecha de pago tampoco: es la constancia de cuándo salió la plata.
    if new.fecha_pago is distinct from old.fecha_pago then
      raise exception 'Una liquidación pagada no cambia de fecha de pago (id %)', old.id
        using errcode = 'check_violation';
    end if;
  end if;

  -- Un pago nuevo lleva la fecha del momento, no una fecha inventada del
  -- futuro. Se tolera un margen por relojes desfasados.
  if new.estado = 'pagado' and new.fecha_pago > now() + interval '1 hour' then
    raise exception 'La fecha de pago no puede estar en el futuro (id %)', new.id
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_liquidaciones_guard_pagado on public.liquidaciones;
create trigger trg_liquidaciones_guard_pagado
  before insert or update on public.liquidaciones
  for each row execute function public.liquidaciones_guard_pagado();

-- Los triggers BEFORE corren en orden alfabético: 'guard' < 'sella', así que
-- el guard rechaza ANTES de que el sellado estampe nada.

commit;
