# Pendiente: no perder facturación del estudio cuando un usuario se va

Fecha de la nota: 2026-08-21. Sale de la segunda auditoría.
**Cambio de esquema — para DESPUÉS del build.** Prioridad alta.

## El problema, medido

El 2026-08-21 se cerró el DELETE directo sobre `usuarios`
(`FIX_TANDA2_2026-08-21.sql`). Eso eliminó el camino *silencioso*, pero **no**
el problema de fondo: `delete-account`, en su paso 5, hace
`admin.from('usuarios').delete().eq('id', uid)` — y `usuarios` **no tiene FK a
`auth.users`**, así que ese DELETE es el que dispara la cascada.

Medido simulando ese paso exacto como `service_role`:

| | Antes | Después |
|---|---:|---:|
| reservas | 5 | 2 |
| créditos facturables | 65 | **30** |
| pagos | 29 | **28** |
| ledger | 15 | 11 |

Hay **12 FKs** hacia `usuarios` con `ON DELETE CASCADE`, incluidas `pagos`,
`reservas` y `creditos_movimientos`.

Dos consecuencias:

1. **El estudio pierde plata.** Su historial cobrable desaparece, así que la
   liquidación del mes le queda corta y no hay forma de reconstruirla.
2. **Se destruyen registros de pago.** Eso no es solo plata: es contabilidad
   que probablemente haya que conservar aunque la persona ejerza su derecho a
   borrarse.

## Opción elegida (a implementar)

**`pagos` y `reservas` pasan de `ON DELETE CASCADE` a `ON DELETE SET NULL`**,
con `usuario_id` / `user_id` nullable. Las filas sobreviven anonimizadas: el
estudio conserva lo que se le debe, la contabilidad queda intacta, y los datos
personales se van con la fila de `usuarios`.

Es el equilibrio entre derecho al olvido y obligación contable: no queda PII,
queda el monto.

## Qué hay que resolver al implementarlo

1. **Migración de las FKs** (`alter table ... drop constraint ... add constraint
   ... on delete set null`) + hacer nullable las columnas.
2. **Todo lo que hace join con `usuarios` asumiendo que existe.** Barrer:
   - `Liquidacion.netoReserva` (no usa el usuario, debería estar OK);
   - `cobros_screen`, `dashboard_estudios_screen`, `admin_liquidaciones_screen`;
   - `reporte-mensual-estudios` (edge);
   - `admin_list_reservas` (muestra el nombre del usuario → mostrar "Usuaria
     eliminada" en vez de romper).
3. **`delete-account`**: revisar si tiene que seguir borrando reservas pasadas.
   Con SET NULL ya no haría falta borrarlas a mano.
4. **Decidir qué pasa con las reservas FUTURAS** de alguien que se borra: hoy
   se cancelan y se devuelven créditos (correcto). Eso no cambia.
5. **Verificar con rollback midiendo efecto**: borrar una usuaria con reservas
   liquidadas y confirmar que los créditos facturables del estudio y el conteo
   de `pagos` **no bajan**.

## Alternativas descartadas

- **Soft-delete** (marcar borrado + anonimizar): más simple, pero deja la fila
  de `usuarios` y hay que anonimizar bien `nombre`/`email` o queda PII.
- **Dejarlo como está**: hoy hay pocos usuarios, pero cada baja se lleva plata
  del estudio en silencio.
