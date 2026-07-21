# Migraciones de Supabase — fuente de verdad

## Regla única

**Lo único que se aplica a la base es `supabase/migrations/`, con `supabase db push`.**

Los `.sql` sueltos en `supabase/*.sql` son historia: se corrieron a mano en su
momento y NO se deben volver a ejecutar. Muchos tienen versiones viejas de
funciones que, si se re-corren, **revierten** cambios posteriores.

## ⚠️ Archivos que NO hay que ejecutar nunca

Correr cualquiera de estos pisa lógica vigente:

| Archivo | Qué revierte si se corre |
|---|---|
| `MIGRACION_COMPLETA.sql` | pricing, cierres, categorías, `admin_upsert_estudio` (todo a versiones viejas) |
| `TANDA_A_SEGURIDAD_Y_TOPES.sql` | ya promovido a migrations + D1; re-correrlo reabre topes viejos |
| `TANDA_B_CATEGORIAS.sql` | idéntico a la migración `20260721180000` |
| `CANCELACION_CIERRE_CONFIGURABLE.sql` | cierres a la versión previa a D1 |
| `CATEGORIAS_MULTIPLES_ESTUDIO.sql` | `admin_upsert_estudio` / `admin_list_studios` viejos |
| `PRICING_DINAMICO.sql` | **reacopla el precio a la categoría** (revierte el desacople) |
| `PRICING_V2_FITNESS_EXPERIENCIA.sql` | `calcular_precio_clase` v2 (pisa la v3 vigente) |
| `GENERAR_CLASES_DESDE_SQL.sql` | `generar_clases_estudio` sin el fix de precio (D3) |
| `COMPLETAR_RESERVAS_CRON.sql` | `completar_reservas_vencidas` sin la ventana de gracia (D1/BUG A) |
| `ROLES_MULTIPLES.sql` | `set_active_estudio` con tipo de retorno distinto (rompe) |

El resto de los `.sql` sueltos (waitlist, empresas, métricas, referidos, etc.)
son la única fuente versionada de esas funciones hasta que se corra el
`db pull` de abajo — no borrarlos.

## Bootstrapear el baseline real (pendiente — puntos 17 y 21)

Varias tablas core (`usuarios`, `reservas`, `clases`, `estudios`,
`liquidaciones`, `creditos_movimientos`, …) y varios RPC
(`consume_user_credits`, `refresh_user_credit_balance`, los `admin_*_pricing_*`)
se crearon desde el dashboard y **su DDL no está en el repo**. No se puede
recrear la base desde cero con lo que hay.

La forma correcta de versionarlos es extraer el esquema REAL de la base:

```
cd ~/aura-flutter
supabase db pull
```

Eso genera una migración nueva en `supabase/migrations/` con el DDL completo y
real de todo lo que hay en producción (tablas, funciones, policies, triggers).
A partir de ahí sí se puede recrear la base entera, y los `.sql` sueltos de
arriba quedan 100% redundantes y se pueden archivar sin riesgo.

> Se dejó como comando a correr y no como migración escrita a mano porque
> reconstruir el DDL de esas tablas/funciones "de memoria" arriesga divergir
> del estado real y romper el ledger de créditos. `db pull` lo hace exacto.
