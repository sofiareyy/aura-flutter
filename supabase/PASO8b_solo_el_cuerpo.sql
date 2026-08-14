-- ============================================================================
-- AURA — PASO 8b: solo el cuerpo de grant_user_credits
-- ============================================================================
-- SOLO LECTURA. Una sola consulta, una sola fila, una sola columna.
--
-- En el dashboard de Supabase, el texto largo a veces se corta en la vista.
-- Si al copiar te queda incompleto, tocá la celda del resultado para
-- expandirla, o usá el botón de copiar de esa celda.

select pg_get_functiondef(p.oid) as cuerpo
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname = 'grant_user_credits';
