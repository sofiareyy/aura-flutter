# Deshacer una asistencia le manda al estudio un mail falso de "nueva reserva"

Anotado el 28/10/2026. **No arreglado**: decisión de Sofía, queda para después.

## Qué pasa

En Asistencia, el estudio marca a alguien como presente. Si se equivocó, toca
el nombre y elige **"Deshacer — marcar como pendiente"**. La reserva vuelve a
`confirmada` y en ese momento **sale el mail de "nueva reserva" al estudio**,
como si alguien acabara de reservar. Es un aviso falso.

## Dónde está

- **App**: `lib/screens/asistencia/asistencia_screen.dart`, línea ~2094. El
  botón llama a `_marcarAsistente(asistente, 'confirmada')`, que hace un
  `update` directo de `reservas.estado` (y pone `checked_in_at` en null).
- **Base**: el trigger `trg_notif_email_nueva_reserva` (AFTER INSERT OR UPDATE
  ON `public.reservas`), función `public.notif_email_nueva_reserva()`. Su filtro
  es:
  ```
  if NEW.estado is distinct from 'confirmada' then return NEW; end if;
  if TG_OP = 'UPDATE' and OLD.estado is not distinct from 'confirmada' then return NEW; end if;
  ```
  Deja pasar cualquier UPDATE que llegue a `confirmada` desde **otro** estado.
  Desde `presente` o `ausente` (el deshacer) también pasa, y manda el mail.
  Copia en el repo: `supabase/EMAIL_ESTUDIO_TRIGGER.sql`. La versión viva se
  lee con `pg_get_functiondef`.

## A la alumna no le llega nada

`notif_email_confirmacion_alumna` sólo manda en un UPDATE si el estado
anterior era `pre_confirmada`. Deshacer no le escribe a la alumna. El problema
es sólo el mail al estudio.

## Arreglo probable (sin aplicar)

En `notif_email_nueva_reserva`, en un UPDATE mandar sólo si `OLD.estado` es
`pre_confirmada`, igual que el trigger de la alumna. Antes de tocarlo, revisar
si existe otro camino legítimo que llegue a `confirmada` por UPDATE y que sí
deba avisar (por ejemplo, la lista de espera).
