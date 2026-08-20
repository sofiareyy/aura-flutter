# Separar datos de cobro de `estudios` + abrir el catálogo a invitados

Fecha: 2026-08-20. **Estado: EN EJECUCIÓN** (ver checklist al final).

## Por qué

`estudios` era a la vez **catálogo público** y **tabla de datos de cobro**. La policy
de SELECT era `to authenticated USING true`, y `estudios_service.getEstudios()` +
`clases_service._attachEstudios()` hacen `.select()` = `select=*`.

⇒ **Cualquier usuaria logueada que abría Explorar recibía en el JSON el `cbu`,
`alias`, `banco` y `titular` de los 9 estudios.** No se mostraba en la UI, pero
viajaba en la respuesta (visible en el Network tab). Leak preexistente, sin
relación con el modo visita.

Y del otro lado: `anon` NO tenía policy sobre `estudios` (verificado: 0 filas con
la anon key, habiendo 9 estudios activos) ⇒ el modo visita mostraba el marketplace
vacío. Las dos cosas tienen la misma causa y el mismo arreglo.

## Por qué NO la vista `estudios_publicos` (opción descartada)

Se evaluó primero. Dos blockers:

1. **Embeds PostgREST.** Hay 5 embeds `estudios(...)` que resuelven contra la
   tabla siguiendo `clases_estudio_id_fkey`. Con la tabla cerrada,
   `estudios!inner(...)` (clases_service.dart:153) **descarta la clase entera** →
   Explorar devuelve CERO clases. Y `estudios(reserva_cierre_minutos)`
   (reservas_service.dart:159) está en el camino de reservar.
2. **Builds publicados sin force-update.** No existe gate de versión en `lib/`
   (busqué `force_update`/`min_version`/`update_required`: cero matches). Cerrar la
   policy de `estudios` rompe Explorar y reservar en toda app vieja de las tiendas.

Separar la tabla evita las dos: `estudios` no cambia de forma, los embeds siguen
resolviendo, y un `select=*` viejo simplemente trae menos columnas.

## Alcance (decidido 2026-08-20)

`estudios_datos_cobro` lleva **8 columnas**:

| Grupo | Columnas | Quién escribe |
|---|---|---|
| Bancarias | `cbu`, `alias`, `banco`, `titular` | la dueña del estudio (y Aura) |
| Comerciales | `comision_aura`, `comision_workshop`, `valor_credito`, `dia_pago` | **solo Aura** |

**`fecha_inicio_cobro` SE QUEDA en `estudios`.** Decisión explícita: no es CBU ni
margen (solo dice desde cuándo Aura cobra comisión), y moverla era lo único del
plan con efecto negativo — en un build viejo llegaría `null` →
`Liquidacion.cobraComision()` daría `true` → el panel de los **6 estudios que hoy
están en período de gracia** mostraría el neto con 30% descontado en vez del 100%.
Se queda y el problema desaparece.

## Estado de los datos (medido antes de migrar)

9 estudios. `comision_aura`=30, `comision_workshop`=15, `valor_credito`=1000,
`dia_pago`=5 en **los 9** (todos default). Con `cbu`: 6. Con `alias`/`banco`/
`titular`: 2. Con `fecha_inicio_cobro`: 6 (13/09 a 30/09/2026, todas futuras).

⇒ Como las comisiones están todas en default, los fallbacks del código
(`?? 30`, `?? 15`, valor global) dan **el número idéntico** en builds viejos.

---

## Los 8 pasos

### Paso 1 — Crear la tabla y migrar

```sql
create table public.estudios_datos_cobro as
select id as estudio_id,
       cbu, alias, banco, titular,
       comision_aura, comision_workshop, valor_credito, dia_pago
  from public.estudios;

alter table public.estudios_datos_cobro
  add primary key (estudio_id),
  add constraint estudios_datos_cobro_estudio_fk
      foreign key (estudio_id) references public.estudios(id) on delete cascade;
```

`create table as` copia datos **y tipos exactos** en una sola sentencia (sin
ventana de pérdida, sin riesgo de type mismatch). `on delete cascade` para que
`admin_delete_estudio` siga andando sin tocarla.

Grants + RLS:

```sql
alter table public.estudios_datos_cobro enable row level security;
revoke all on public.estudios_datos_cobro from anon;
grant select, insert, update on public.estudios_datos_cobro to authenticated;
grant all on public.estudios_datos_cobro to service_role;

create policy "datos_cobro_select" on public.estudios_datos_cobro
  for select to authenticated
  using (public.is_admin() or public.es_miembro_de_estudio(estudio_id));

create policy "datos_cobro_update" on public.estudios_datos_cobro
  for update to authenticated
  using  (public.is_admin() or public.es_miembro_de_estudio(estudio_id))
  with check (public.is_admin() or public.es_miembro_de_estudio(estudio_id));

create policy "datos_cobro_insert" on public.estudios_datos_cobro
  for insert to authenticated
  with check (public.is_admin() or public.es_miembro_de_estudio(estudio_id));
```

Trigger que impide que un estudio se auto-edite las comerciales (mismo patrón que
`estudios_bloquear_columnas_aura`: exime a `service_role`/`postgres`, o sea a los
RPC `SECURITY DEFINER` del backoffice):

```sql
create function public.datos_cobro_bloquear_columnas_aura() returns trigger
language plpgsql set search_path to 'public' as $$
begin
  if current_user not in ('authenticated','anon') then return new; end if;
  if new.comision_aura     is distinct from old.comision_aura
  or new.comision_workshop is distinct from old.comision_workshop
  or new.valor_credito     is distinct from old.valor_credito
  or new.dia_pago          is distinct from old.dia_pago then
    raise exception 'Comisiones y precios los define Aura desde el backoffice';
  end if;
  return new;
end $$;

create trigger trg_datos_cobro_columnas_aura
  before update on public.estudios_datos_cobro
  for each row execute function public.datos_cobro_bloquear_columnas_aura();
```

> **`estudios_bloquear_columnas_aura()` NO se toca en este paso.** Sigue
> protegiendo las columnas viejas mientras existan (dual-write). Se reescribe
> recién en el paso 8, junto con el DROP.

### Paso 2 — Verificar la migración

Las dos tienen que dar **0**:

```sql
-- (a) ninguna fila de más ni de menos
select count(*) from public.estudios e
  full outer join public.estudios_datos_cobro d on d.estudio_id = e.id
 where e.id is null or d.estudio_id is null;

-- (b) ningún valor distinto (is distinct from maneja NULL bien)
select count(*) from public.estudios e
  join public.estudios_datos_cobro d on d.estudio_id = e.id
 where e.cbu is distinct from d.cbu
    or e.alias is distinct from d.alias
    or e.banco is distinct from d.banco
    or e.titular is distinct from d.titular
    or e.comision_aura is distinct from d.comision_aura
    or e.comision_workshop is distinct from d.comision_workshop
    or e.valor_credito is distinct from d.valor_credito
    or e.dia_pago is distinct from d.dia_pago;
```

Más: control visual de las 9 filas, y probar con la **anon key** que
`estudios_datos_cobro` devuelva 0 filas / 401.

### Paso 3 — Funciones de la base (con DUAL-WRITE)

Siguen escribiendo en **las dos** tablas hasta el paso 8, así el rollback es
`drop table` y nada se pierde.

| Función | Cambio |
|---|---|
| `admin_upsert_estudio` | **Firma idéntica.** Parte el write: catálogo → `estudios`, cobro → upsert en la nueva. `fecha_inicio_cobro` sigue en `estudios`. Dual-write. |
| `admin_list_studios` | **`RETURNS TABLE` idéntico.** Agrega `left join estudios_datos_cobro d`; `comision_aura`/`comision_workshop`/`cbu` salen de `d`, `fecha_inicio_cobro` de `e`. |
| `estudios_bloquear_columnas_aura` | **sin cambios hasta el paso 8** |
| `admin_dashboard_metrics` | `coalesce(e.valor_credito, 6000)` → join a la nueva |
| `admin_pricing_snapshot` | `avg(e.valor_credito)` → join a la nueva |
| `admin_set_valor_credito_ars` | `update estudios set valor_credito` → dual-write |
| `admin_update_global_credit_value` | idem |
| `recalc_pack_prices` | **sin cambios** (solo lee `configuracion_global`) |

Mantener las firmas es lo que deja `admin_estudios_screen` y
`admin_service.saveEstudio` **sin tocar**.

### Paso 4 — Edge functions (2) + redeploy

Usan `service_role` (RLS no aplica) pero piden las columnas por nombre:

- `aviso-cobro-manana/index.ts:68`
- `reporte-mensual-estudios/index.ts:79`

Ambas: `select('id, nombre, comision_aura, comision_workshop, valor_credito, fecha_inicio_cobro')`
→ embed de `estudios_datos_cobro` + aplanar antes de pasarlo a
`_shared/liquidacion.ts` (que no se toca). `fecha_inicio_cobro` sigue saliendo de
`estudios`.

⚠️ **NO invocar `reporte-mensual-estudios` para testear — manda mails reales
(Resend).** Verificar leyendo.

### Paso 5 — Dart (7 sitios)

Truco central: **`estudio_admin_service` devuelve el estudio con los datos de cobro
aplanados en el mismo map**, así `cobros_screen`, `perfil_estudio_screen`,
`dashboard_estudios_screen` y `mis_clases_screen` siguen leyendo `_estudio['cbu']`
y `Liquidacion.*(_estudio)` sin cambiar una línea.

Lecturas:
- `estudio_admin_service.dart:98` → `.select('*, estudios_datos_cobro(*)')` + aplanar
- `perfil_estudio_screen.dart:103,154,195,247` → idem
- `admin_liquidaciones_screen.dart:98` → embed
- `admin_pricing_screen.dart:91` → saca `comision_workshop, comision_aura` del select

Escrituras:
- `perfil_estudio_screen.dart:1064` → `upsert` en `estudios_datos_cobro`
  (las de 623 = `categorias` y 812 = `descripcion` quedan en `estudios`)
- `admin_pricing_screen.dart:171,230` → la parte de `comision_workshop` a la nueva

Sin cambios: todo el browse, `cobros_screen`, `dashboard_estudios_screen`,
`mis_clases_screen`, `admin_estudios_screen`, `admin_service`.

### Paso 6 — Probar en Chrome logueado

Explorar / reservar / perfil / panel de estudio, sin regresión. **Gate de
confirmación con la usuaria.**

### Paso 7 — Abrir el catálogo a invitados

```sql
alter policy "todos pueden ver estudios" on public.estudios to anon, authenticated;
```

Reusa la policy existente (`USING true`) en vez de crear una segunda. `anon` ya
tiene `GRANT SELECT` de tabla. No gana escritura: las únicas policies de write son
`to authenticated`.

### Paso 8 — DROP de las columnas viejas (SOLO con 1-7 en verde)

```sql
alter table public.estudios
  drop column cbu, drop column alias, drop column banco, drop column titular,
  drop column comision_aura, drop column comision_workshop,
  drop column valor_credito, drop column dia_pago;
```
+ reescribir `estudios_bloquear_columnas_aura()` (le quedan `creditos_min`,
`creditos_max`, `tipo_precio`, `horarios_config`, `precio_config`,
**`fecha_inicio_cobro`**) + sacar el dual-write.

Verificación final: `estudios?select=*` con la **anon key** no devuelve ninguna
columna sensible.

---

## Impacto en builds viejos (sin force-update)

Un build viejo hace `select=*` → recibe **30 columnas en vez de 38**. No es error,
es payload más chico; los campos faltantes llegan `null` y todo se lee con
fallback.

- **Usuario común: cero impacto.** Ninguna pantalla del browse lee una columna que
  se mueve.
- **Dueña de estudio: los campos de CBU/alias/banco/titular aparecen vacíos** en su
  panel hasta que actualice. El dato no se pierde.
- Comisiones y `valor_credito`: sin divergencia, los 9 estudios están en default.
- `fecha_inicio_cobro`: **sin divergencia**, se queda en `estudios`.

## Rollback

En cualquier punto antes del paso 8: `drop table public.estudios_datos_cobro cascade`
+ revertir funciones. La tabla vieja nunca dejó de ser la fuente válida (dual-write).

---

## Checklist

- [x] 1. Tabla + datos + PK/FK + RLS + trigger — **APLICADO 2026-08-20**
- [x] 2. Verificación (0 y 0) + anon bloqueado — **VERDE 2026-08-20** (ver abajo)
- [x] 3. Funciones de la base (dual-write) — **APLICADO 2026-08-20** (+1 RPC nuevo)
- [x] 4. 2 edge functions + redeploy — **APLICADO 2026-08-20**
- [x] 5. Dart + analyze (84 issues = baseline, 0 errores) + build web OK — **2026-08-20**
- [x] 6. Chrome logueado sin regresión — **VERDE 2026-08-20** (usuario común,
      dueña de estudio con CBU editado y persistido, backoffice)
- [x] 8→7 **ORDEN INVERTIDO** (ver abajo): dual-write removido + rebuild → DROP
      de las 8 columnas → recién ahí `alter policy ... to anon`.
      **COMPLETADO 2026-08-20.**

## ⚠️ Corrección de orden (importante para futuras migraciones así)

El plan original ponía el paso 7 (abrir a `anon`) ANTES del paso 8 (DROP). Eso
habría dejado una ventana en la que `estudios` era legible por `anon` **con las
columnas bancarias todavía adentro**: cualquiera con la anon key —que es pública
y va compilada en el bundle web— podía pedir `estudios?select=cbu` y llevarse los
9 CBU. Se invirtió: **primero borrar, después abrir.**

## Resultado final (2026-08-20)

- `estudios` quedó con 30 columnas, ninguna sensible. `fecha_inicio_cobro` sigue ahí.
- Usuaria común logueada, `select=*` sobre `estudios`: 9 filas, **0 columnas sensibles**.
- `anon` con la anon key: ve el catálogo (30 columnas, ninguna sensible); pedir
  `cbu`/`comision_aura`/`valor_credito` explícitamente devuelve **HTTP 400,
  columna inexistente**.
- `estudios_datos_cobro` para `anon`: **HTTP 401**. Para usuaria común: **0 filas**.
- `usuarios`/`reservas`/`pagos`/`creditos_movimientos` para `anon`: **0 filas**.
- Embed `clases → estudios!inner` funcionando para invitado (Explorar deja de
  estar vacío).
- Backoffice post-DROP: `admin_list_studios` → 9 estudios, 6 CBU, 6 fechas.
- Panel de dueña post-DROP: lee su estudio + sus datos de cobro.

## Resultado de la verificación de los pasos 1-2 (2026-08-20)

Integridad:
- (a) filas de más/menos: **0**
- (b) valores distintos: **0**
- 9 filas migradas, 6 con CBU, 2 con alias/banco/titular, comisiones 30/15,
  valor_credito 1000, dia_pago 5 — idénticas al origen.
- Tipos copiados: `estudio_id integer`, `cbu/alias/banco/titular text`,
  `comision_aura numeric`, `comision_workshop integer`, `valor_credito numeric`,
  `dia_pago integer`.
- `fecha_inicio_cobro`: sigue en `estudios`, NO está en la nueva. ✓

Lectura (RLS simulada con `set local role authenticated` + jwt claims):

| Sujeto | Filas visibles | CBUs |
|---|---|---|
| usuaria común | **0** | 0 |
| dueña de estudio 1 | **1** (solo el 1) | 0 (ese estudio no tiene CBU) |
| admin de Aura | **9** | 6 |

`anon` vía REST → **HTTP 401** en `select=*`, `select=cbu` y `select=estudio_id`
(el `revoke` corta antes de llegar a RLS).

Escritura (todo en transacción + rollback, contando filas afectadas):

| Prueba | Resultado |
|---|---|
| dueña edita SU cbu | 1 fila ✓ |
| dueña edita SU comisión | excepción del trigger ✓ |
| dueña edita cbu de otro estudio | 0 filas ✓ |
| usuaria común edita cbu ajeno | 0 filas ✓ |
| admin de Aura edita cualquier cbu | 1 fila ✓ |

Integridad post-pruebas: 0 filas divergentes (nada quedó modificado).

## Desvíos respecto del plan original (pasos 3-5)

1. **`admin_list_studios` estaba ROTA desde antes.** El `RETURNS TABLE` declara
   `id bigint` pero `estudios.id` es `integer` → `RETURN QUERY` tira 42804 en
   cada llamada. Está así desde `COMISION_FECHA_INICIO_COBRO.sql:114`. Nadie lo
   notó porque `AdminService.listEstudios()` tiene un `catch (_)` que cae a leer
   `from('estudios').select()`. ⇒ **el backoffice venía corriendo por el
   fallback.** Se arregló con casts explícitos, y además se repuntó el fallback
   de Dart (que si no, el paso 8 le vaciaba los CBU al form de edición).
2. **Un RPC nuevo: `admin_set_comision_workshop(p_estudio_id, p_comision)`.**
   `admin_pricing_screen` escribía `comision_workshop` directo sobre `estudios`;
   ahora la columna está protegida por trigger. NO se reusó
   `admin_upsert_estudio`: en modo UPDATE asigna `barrio`/`direccion`/
   `descripcion`/`foto_url`/`instagram`/`whatsapp`/`web`/`lat`/`lng`/
   `fecha_inicio_cobro` **sin `coalesce`**, así que una llamada parcial le
   borraría esos campos al estudio.
3. **Sitios de Dart: 6, no 7.** `perfil_estudio_screen:154/195/247` resultaron
   ser updates de `foto_url`/`galeria_urls`, no lecturas. Se sumó
   `admin_service.listEstudios` (el fallback del punto 1) y el helper nuevo
   `lib/utils/datos_cobro.dart`.

## ✅ Fix posterior (2026-08-20): valor_credito 6000 + fila de cobro automática

Dos cosas sobre que **un estudio nuevo nazca bien**. Solo base, sin build ni deploy.

**1. `valor_credito` DEFAULT 6000 → DEFAULT NULL.** El 6000 era de cuando un
crédito valía eso; hoy `configuracion_global.valor_credito_ars` = 1000. Un
estudio creado hoy nacía en 6000 y liquidaba 6x.

NULL y **no** 1000 a propósito: `ValorCredito.deEstudio()` (Dart) y
`valorCredito()` (`_shared/liquidacion.ts`) ya interpretan null/0 como "usá el
global". Con NULL la columna pasa a significar lo que debía —**override por
estudio**— y el valor sale siempre fresco del global. Un DEFAULT fijo, o uno
calculado al INSERT, congelaría el número y se volvería a desactualizar: es el
mismo bug con otra cara.

**2. Helper `valor_credito_global()`** (lee `configuracion_global`, fallback
duro 1000). Reemplaza los dos últimos `6000` hardcodeados, que estaban en
`admin_dashboard_metrics` y `admin_pricing_snapshot`. El código de la app ya
estaba limpio desde que se creó `valor_credito.dart`.

**3. Trigger `trg_estudios_datos_cobro` (AFTER INSERT ON estudios).** Había dos
caminos de creación y uno quedó cojo tras esta migración: el backoffice "solo
estudio" va por `admin_upsert_estudio` (que sí crea la fila de cobro), pero
"con cuenta" va por la edge `admin-crear-estudio`, que hace un INSERT directo
sobre `estudios` (línea 84) y no sabe que la tabla existe. El trigger cubre
**todos** los caminos, presentes y futuros, sin redeployar la edge function.
Usa `on conflict do nothing` para no pisar el upsert de `admin_upsert_estudio`.

### Verificación (todo en transacción + rollback)

| Prueba | Resultado |
|---|---|
| Camino 1 (RPC `admin_upsert_estudio`) | fila de cobro creada, `valor_credito = NULL`, com 30 / ws 15 / dia 5 |
| Camino 2 (INSERT directo, como la edge) | fila de cobro creada, `valor_credito = NULL`, com 30 / ws 15 / dia 5 |
| Cuánto liquida el estudio nuevo | propio=NULL → **efectivo 1000** → 10 créditos = 10.000 ARS (no 60.000) |
| Los 9 existentes | **sin tocar**: los 9 siguen en 1000, 0 en 6000, 0 nulos |
| `admin_pricing_snapshot` | 1000 = baseline |
| `admin_dashboard_metrics` | usuarios=74, estudios=9/9, reservas=5, créditos=30, ingresos=30000, ocup=1, top=Hot Clic — **idéntico al baseline** |
| Estudios de prueba dejados | 0 (9 estudios, 9 filas de cobro) |
| `6000` restante en alguna función | ninguna |

## Hallazgos colaterales (NO son parte de este plan)

- ✅ **`valor_credito` default 6000 — ARREGLADO 2026-08-20** (ver abajo).

- 🟠 `lista_espera` tiene policy `waitlist_count_public` con `USING true` y
  `roles={public}` → cualquiera, `anon` incluido, puede leer todas las filas **con
  `usuario_id`**. Hoy la tabla tiene 0 filas, así que no hay dato expuesto, pero
  queda armado. `LISTA_ESPERA_arreglar_y_asegurar.md` cubre las *funciones*, no
  esta policy.
- 🟡 `study_reviews` con `USING true` expone `usuario_id` a `anon` (bajo impacto:
  el UUID solo no se cruza con `usuarios`, que está cerrada).
- 🟢 `configuracion_global`: la policy se llama "Admins leen config" pero tiene
  `USING true`. Sin impacto real (4 claves de negocio, sin secretos) pero el nombre
  confunde — conviene renombrarla.
- El invitado va a ver **ocupación falsa** (todas las clases con cupo libre) porque
  `reservas` está cerrada para `anon`. Para disponibilidad real hace falta un
  RPC/vista agregada. Decisión de producto, aparte.
