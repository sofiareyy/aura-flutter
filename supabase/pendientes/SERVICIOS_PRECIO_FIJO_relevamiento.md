# Servicios de precio fijo — relevamiento (Tanda D)

Medido contra la base el 2026-08-26. **Nada construido.**

Concepto: Aura configura desde el backoffice un precio fijo para un servicio de
UN estudio ("sauna de X = 8 créditos"). Cuando ese estudio carga un horario y
elige ese servicio, el precio se pone solo, **sin valle/pico**. Las clases
normales del mismo estudio siguen con su rango.

## 1. El hallazgo que hace esto barato

**`calcular_precio_clase(p_estudio_id, p_categoria, p_dia, p_hora)` ya recibe
`p_categoria`… y la ignora por completo.** Y **los tres llamadores le pasan
`null`**.

Esa función es el **único cuello** por donde pasa todo el precio del sistema.
Si la búsqueda del precio fijo vive ahí adentro, todo lo demás lo respeta solo.
No hay que tocar el generador ni inventar excepciones repartidas.

## 2. Quién pisa el precio hoy — son CINCO, no dos

| Quién | Cuándo corre | Qué hace hoy |
|---|---|---|
| `horarios_fijos_fija_precio` (trigger) | el estudio guarda un horario | **pisa** `creditos` con valle/pico. Pasa `null` de categoría. **Es el que bloquea la idea.** |
| `clases_fija_precio` (trigger) | se crea/edita una clase | **pisa** `creditos`. Pasa `null`. |
| `generar_clases_estudio` (cron 03:00) | todas las noches | ✅ **el PRECIO ya lo respeta**: `if coalesce(v_h.creditos,0) > 0 then v_creditos := v_h.creditos`. ⚠️ pero la **ETIQUETA** (`tipo_precio`) la recalcula siempre ⇒ un servicio fijo saldría marcado "valle" o "pico". |
| `admin_recalcular_precios_estudio` | cada vez que guardás precios en el backoffice | **pisa `clases` Y `horarios_fijos`**. El más peligroso: pasa por arriba de todo de una. |
| `admin_set_precio_clases_futuras` | manual | pone un número fijo a todas las futuras. |

> **La buena noticia:** el cron nocturno **no es el problema**. Ya respeta el
> precio del horario fijo (fix "D3"). El que pisa es el **trigger**, antes; el
> generador después propaga fielmente lo que el trigger dejó.

Los dos triggers salen por `if current_user not in ('authenticated','anon')`,
así que el cron (service_role) no los dispara. El daño ocurre **cuando el
estudio guarda desde la app**.

## 3. Dónde se guardaría el precio

⚠️ **No puede ir en `study_categories`: esa tabla es GLOBAL** (id, nombre,
activa — sin `estudio_id`) y ya tiene "Spa", "Recovery", "Meditación",
"Ceramica". El precio es **por estudio**, así que hace falta una tabla puente:

```
estudio_servicios_precio
  estudio_id  bigint  -> estudios(id)
  servicio    text                      -- la categoría/servicio
  creditos    int                       -- precio único
  activo      bool
  primary key (estudio_id, servicio)
```

Y `calcular_precio_clase` arranca con: *si hay fila activa para
(estudio, categoría) ⇒ devolver ese precio con `tipo = 'servicio'` y listo.*

## 4. Base vs Dart

**Base (sale sin build, se aplica cuando quieras):**
- la tabla nueva + sus policies
- `calcular_precio_clase`: la búsqueda al principio
- los 2 triggers: pasar la categoría en vez de `null`
- `admin_recalcular_precios_estudio`: pasar la categoría (o saltear los fijos)
- `generar_clases_estudio`: que la etiqueta no pise `'servicio'`
- RPC `admin_set_servicio_precio` para el backoffice

**Dart (necesita build):**
- backoffice: pantalla para cargar "servicio + precio" por estudio
- panel del estudio: que al elegir el servicio muestre *"Sauna · 8 créditos
  (precio único)"* en vez del rango
- Explorar: que un servicio de precio fijo **no** muestre badge de valle/pico

> Ojo con la interacción: el badge "PRECIO REDUCIDO" que arreglé hoy compara
> contra `estudios.creditos_max`. Un servicio fijo de 8 en un estudio con techo
> 18 daría "precio reducido" siendo precio único. Hay que excluirlo.

## 5. Las decisiones de borde — esto es lo que falta definir

1. **¿Qué campo identifica el servicio?** El formulario de grilla escribe
   `categorias` (**array, multi-select**), no `categoria` (texto). Y medido:
   **61 de 115 horarios fijos no tienen ninguna categoría**. Opciones: usar el
   array, exigir una categoría única, o un campo `servicio` aparte.
2. **Si un horario tiene varias categorías y dos tienen precio fijo, ¿cuál
   gana?** Hay que fijar una regla (la más cara, la más barata, o prohibir más
   de una con precio fijo).
3. **Al cambiar el precio de un servicio, ¿qué pasa con lo ya cargado?**
   ¿Se recalculan las futuras? ¿Y las que ya tienen reservas? (hoy
   `admin_recalcular_precios_estudio` recalcula **todas, pasadas incluidas**).
4. **¿El precio fijo salta el bloqueo de "falta configurar el precio"?**
   Hoy un estudio sin rango configurado **no puede cargar nada**. Un estudio
   sólo-spa no tiene valle/pico y nunca los va a tener. Si el servicio fijo
   alcanza, se destraba un caso de negocio entero.
5. **¿Qué etiqueta lleva?** `tipo_precio` hoy es normal/valle/pico/experiencia.
   Hace falta `'servicio'` (o similar) o Explorar va a mentir.
6. **¿Aplica también a la clase suelta**, o sólo a la grilla?
7. **¿La comisión de liquidación es la misma?** Hoy hay `comision_aura` y
   `comision_workshop`. Un sauna, ¿va por la de clase?
8. **¿Un sauna es una "clase"?** Cupo 1, 30 minutos, sin instructor. Reutilizar
   `clases` es lo barato; el riesgo es que aparezca mezclado en Explorar como
   si fuera una clase grupal.

## 6. Cómo se vería

**Backoffice (Aura):** dentro de la pantalla de precios del estudio, una
sección nueva "Servicios de precio fijo": elegir servicio del catálogo global,
poner créditos, guardar. Lista de los cargados, con editar y desactivar.

**Panel del estudio:** al cargar un horario y elegir la categoría, si esa
categoría tiene precio fijo el formulario muestra
*"Sauna · 8 créditos · precio único, no varía por horario"* y **deja de
mostrar el chip de franja**. Hoy los chips dicen `🌙 08:30 · 12 cr`.

## 7. Conexión con el running club

Este mecanismo es también el que destraba la **clase gratis recurrente**
(ver `aura-running-club-caso-de-uso-modelo-c` en memoria): hoy es imposible
porque el trigger le pisa el precio con la franja. Un servicio de precio fijo
en 0 créditos es exactamente eso. Ya existe una categoría **"GRATIS"** suelta
en `study_categories` de esa exploración.
**Decidir si el mismo mecanismo cubre los dos casos** antes de construir dos.
