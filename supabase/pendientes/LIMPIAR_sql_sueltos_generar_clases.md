# Pendiente: limpiar copias viejas de generar_clases_* en los SQL sueltos

Fecha de la nota: 2026-08-19. **No urgente**, pero que quede.

## Qué

El 2026-08-19 se le agregó un guard de seguridad a `generar_clases_estudio` y
`generar_clases_todos_estudios` (validar el caller: `es_miembro_de_estudio`, y
`todos_estudios` solo service_role). Se aplicó sobre el **desplegado** vía la
Management API (ver `EMAIL_ESTUDIO_TRIGGER.sql` para el patrón de aplicación a
mano; el DDL de este fix quedó sin archivo en el repo).

**Riesgo:** hay copias VIEJAS (sin el guard) de estas funciones en varios SQL
sueltos del repo. Si alguien los re-corre, hacen `create or replace` y
**revierten el fix** (vuelven a dejar las funciones abiertas a cualquiera).

## Copias a revisar / actualizar (o borrar si son obsoletas)

- `supabase/GENERAR_CLASES_DESDE_SQL.sql`
- `supabase/MIGRACION_COMPLETA.sql`
- `supabase/CANCELACION_CIERRE_CONFIGURABLE.sql`
- `supabase/TANDA_B_CATEGORIAS.sql`
- `supabase/migrations/20260721180000_categorias_crud_y_multiples.sql`
- (buscar todas con: `grep -rl "function public.generar_clases_estudio" supabase/`)

## Qué hacer

Para cada copia: o bien **agregarle el mismo guard** (para que quede consistente
con el desplegado), o **borrarla** si ya no se usa. Idealmente, dejar UNA sola
fuente de verdad de estas funciones (con el guard) y sacar las duplicadas.

El guard aplicado (referencia):
```sql
-- generar_clases_estudio, al inicio del begin:
if auth.uid() is not null and not public.es_miembro_de_estudio(p_estudio_id::bigint) then
  return json_build_object('creadas', 0, 'omitidas', 0, 'error', 'no_autorizado');
end if;
-- generar_clases_todos_estudios, al inicio:
if auth.uid() is not null then
  return json_build_object('estudios', 0, 'creadas', 0, 'omitidas', 0, 'error', 'no_autorizado');
end if;
-- + revoke execute ... from anon (estudio) / from anon, authenticated (todos)
```

Mismo tipo de riesgo (historial de migraciones desincronizado) aplica a los otros
fixes aplicados a mano; esta nota es específica de generar_clases_* por el pedido.
