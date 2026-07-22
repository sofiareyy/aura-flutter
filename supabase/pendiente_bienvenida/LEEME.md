# Bienvenida — migración en espera

Esta migración NO está en `supabase/migrations/`, así que `supabase db push`
NO la aplica. Queda separada a pedido: se aplica el arreglo de gift card +
referidos ahora, y la bienvenida más adelante.

El código Dart de bienvenida YA está en la app (login hook, pop-up en home,
toggle en el backoffice), pero tolera que esta migración no esté aplicada:
las llamadas a `acreditar_bienvenida` y `bienvenida_esta_activa` están en
try/catch y no rompen nada si los RPC no existen todavía.

⚠️ NO tocar el toggle "Créditos de bienvenida" en Admin → Config hasta aplicar
esta migración (los RPC admin_encender/apagar_bienvenida no existen aún y
tiraría error).

## Para aplicarla después
1. Mover el .sql de vuelta a supabase/migrations/ con un timestamp NUEVO
   (posterior a la última aplicada), p.ej. renombrándolo con la fecha del día:
     git mv supabase/pendiente_bienvenida/20260723110000_bienvenida_creditos_apagado.sql \
            supabase/migrations/AAAAMMDDHHMMSS_bienvenida_creditos_apagado.sql
2. supabase db push
3. Queda con el flag en OFF: encender desde Admin → Config cuando se lance.
