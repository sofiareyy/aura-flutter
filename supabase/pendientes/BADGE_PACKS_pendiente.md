# Pendiente: columna `badge` en `pricing_credit_packs`

Fecha de la nota: 2026-08-19. Requiere CLI de Supabase linkeado (cambio de base).

## Contexto

En el fix 5, `PricingService.getPacks()` pasó a leer los packs desde la tabla
`pricing_credit_packs` (antes se calculaban en el cliente). La tabla solo tiene
un booleano `popular`, así que el badge de la app se deriva así:

```dart
'badge': row['popular'] == true ? 'MÁS POPULAR' : null,
```

Eso conserva el **"MÁS POPULAR"** del Pack Esencial (`popular = true`), pero se
**perdió el "MEJOR VALOR"** del Pack Popular, que en el cálculo viejo era un
badge distinto y `popular = false` en la tabla no lo captura.

"MEJOR VALOR" es herramienta de venta — hay que recuperarlo bien desde la tabla,
no hardcodeado en el cliente.

## Qué hacer cuando se linkee el CLI

1. Agregar una columna de texto para el badge (nullable) en `pricing_credit_packs`:

   ```sql
   alter table public.pricing_credit_packs
     add column if not exists badge text;

   update public.pricing_credit_packs set badge = 'MÁS POPULAR' where nombre ilike 'Pack Esencial';
   update public.pricing_credit_packs set badge = 'MEJOR VALOR' where nombre ilike 'Pack Popular';
   -- Prueba y Full quedan con badge NULL.
   ```

2. En `lib/services/pricing_service.dart`, `_packDesdeFila()`: leer el badge de
   la columna en vez de derivarlo de `popular`:

   ```dart
   'badge': (row['badge']?.toString().trim().isNotEmpty ?? false)
       ? row['badge'].toString()
       : (row['popular'] == true ? 'MÁS POPULAR' : null),
   ```

   (El fallback a `popular` deja el comportamiento sano si la columna todavía no
   existe o viene vacía.)

3. `popular` se sigue usando en la app por compat, así que la columna se queda.

---

# Pendiente: lista de espera (calcular el puesto)

Fecha de la nota: 2026-08-19. Requiere CLI de Supabase linkeado (verificación de RLS).

Ver también auditoría item **B3** y `BUILD_IOS_pendiente.md`.

## Contexto

`reservas_service.dart:449` (`getListaEsperaUsuario`) pide la columna
`lista_espera.posicion`, que **no existe** → 400. Además filtra
`.eq('usuario_id', uid)`, así que solo ve las filas del propio usuario: con ese
filtro es imposible calcular el puesto (haría falta contar a los que entraron
antes en esa clase).

Decisión de la auditoría: **NO se agrega la columna `posicion`**. El puesto se
deriva por `created_at`, en Dart o vía vista/RPC.

## Qué verificar cuando se linkee el CLI (2 min)

1. Que `lista_espera` tenga `created_at` (la tabla se creó a mano, no está en
   migraciones — confirmar el nombre real de la columna).
2. **RLS: que un usuario normal pueda leer las filas de OTROS usuarios de una
   misma clase** (`select ... where clase_id = X`, sin filtrar por usuario).
   `WaitlistService.getCount()` ya depende de esto.

## Según el resultado

- **RLS permisivo** → resolver **Dart-only**: cambiar la query para leer por
  `clase_id` ordenado por `created_at` y derivar el puesto como el índice + 1.
- **RLS restrictivo** (solo ve lo propio) → hace falta un **RPC/vista
  `SECURITY DEFINER`** con `row_number() over (partition by clase_id order by
  created_at)`. NO resolver en Dart: devolvería puestos silenciosamente
  incorrectos.
