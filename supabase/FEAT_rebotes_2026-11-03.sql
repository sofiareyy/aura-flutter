-- Rebotes y quejas de spam cuentan como baja permanente (3/11/2026).
-- Pedido de Sofía: "si una dirección rebota una vez, que no se le vuelva a
-- mandar nunca". Se guardan en la misma tabla que las bajas, con su origen,
-- así todos los envíos que ya miran mail_bajas las saltean sin cambiar nada.
alter table public.mail_bajas drop constraint if exists mail_bajas_origen_check;
alter table public.mail_bajas add constraint mail_bajas_origen_check
  check (origen in ('link', 'gmail', 'manual', 'rebote', 'queja'));

-- 'rebote_apple': direcciones @privaterelay.appleid.com que rebotan porque
-- Aura no está registrada en el relay de Apple (no son cuentas falsas). Se
-- separan para poder liberarlas cuando se registre el dominio.
alter table public.mail_bajas drop constraint if exists mail_bajas_origen_check;
alter table public.mail_bajas add constraint mail_bajas_origen_check
  check (origen in ('link', 'gmail', 'manual', 'rebote', 'rebote_apple', 'queja'));
update public.mail_bajas set origen = 'rebote_apple'
 where origen = 'rebote' and email like '%@privaterelay.appleid.com';
