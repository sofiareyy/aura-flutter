# Qué le pasa a la alumna anotada cuando el estudio toca la grilla

Relevado y **medido contra la base el 2026-08-28**. Nada construido.
🔴 **Urgente: antes del 13/9**, que es cuando arrancan las reservas reales.

## Estado hoy: 0 exposición, pero el gatillo está armado

**Medido: 0 clases futuras de grilla con reserva activa.** Hoy no muerde. El
13/9 sí.

---

## Los 6 escenarios, medidos

| | Qué hace el estudio | Qué le pasa a la alumna HOY | ¿Avisa? | ¿Devuelve? |
|---|---|---|---|---|
| 1 | **Mueve la grilla** (día/hora) | 🔴 **La clase se le mueve debajo de los pies** | ❌ **NO** | ❌ no |
| 2 | **Borra una clase con anotadas** | ✅ **Bloqueado** por el candado | — | — |
| 3 | **Borra sólo la grilla** | 🟠 La clase queda **huérfana pero viva** | ❌ no | ❌ no |
| 4 | **Baja el cupo** por debajo de las anotadas | 🟠 Cupo 1 con **3 anotadas**: nadie se cae, pero el número miente | ❌ no | ❌ no |
| 5 | **Cambia el precio** | ✅ Sano: la clase pasa a 20, **a ella le siguen cobrados 12** | — | — |
| 6 | **Cancela una clase puntual** | ✅ **El camino bueno**: `cancelada_por_estudio` + campanita + créditos | ✅ sí | ✅ sí |

### El detalle del escenario 1 (el grave)

Medido: grilla jueves 10:00 con una alumna anotada → el estudio la pasa a
sábado 18:00 →

```
clase 6095 · fecha 2026-09-05 18:00 · reserva confirmada · le_avisaron: 0
```

La reserva **sigue viva y su QR sigue sirviendo**, pero para **otro día y otra
hora**. Ella se entera si abre la app. Si no, va el jueves a las 10 y no hay
nadie.

El trigger `horarios_fijos_mover_clases` (24/8) mueve las futuras a propósito
—es lo correcto para el estudio— pero **no mira si hay alguien anotado** y
**no avisa a nadie**. Del lado del panel tampoco hay ningún chequeo previo:
`_propagarHorarioFijoAClasesFuturas` propaga nombre, profe, cupo, créditos y
categorías sin consultar reservas.

### Y una colisión que apareció midiendo

Mover una grilla **puede dejar dos clases en el mismo minuto**. El trigger
`horarios_fijos_sin_duplicados` protege contra dos *horarios* iguales, pero
**no contra las clases movidas cayendo encima de una clase suelta**. Medido:

```
2026-09-05 18:00 · 2 clases en el mismo minuto · "Clase suelta + Grilla A"
```

Las dos con alumnas anotadas, las dos publicadas.

---

## Qué debería pasar — propuesta

La usuaria ya eligió el patrón en su momento: **mover + avisar**. El mecanismo
existe y está probado — es el mismo del escenario 6.

| | Escenario | Comportamiento propuesto |
|---|---|---|
| 1 | Mueve la grilla | **Mover igual + campanita/mail a cada anotada** con el antes y el después ("Tu clase del jueves 10:00 pasó al sábado 18:00"). Y que la alumna pueda **cancelar sin penalidad** aunque esté fuera de la ventana: el cambio no fue decisión suya |
| 3 | Borra la grilla | Que las clases futuras **sin** reservas se borren y las **con** reservas se **cancelen** con devolución + aviso (como el 6), en vez de quedar huérfanas |
| 4 | Baja el cupo | **Rechazar** si el cupo nuevo es menor que las anotadas, con el número: *"Hay 3 anotadas, no podés dejar 1 lugar"*. Nunca elegir a quién sacar |
| 6 | Cancela una clase | ✅ Ya está bien. Es el modelo a copiar |
| — | Colisión al mover | **Rechazar el movimiento** si deja dos clases del estudio en el mismo minuto, con el mismo mensaje que ya usa el guard de grillas |

**Decisión que falta:** ¿el aviso del escenario 1 va sólo por campanita, o
también por mail? El mail **llega hoy** (Resend anda); el push **no** (APNs
roto). Para un cambio de horario, el mail parece lo mínimo.

---

## Base vs Dart

### 🟢 BASE — lo esencial, sin build
1. `horarios_fijos_mover_clases`: además de mover, **insertar en
   `notificaciones_usuario`** una fila por alumna anotada (eso ya dispara
   campanita + push cuando APNs esté) y, si se decide, disparar el mail.
2. **Guard de colisión** dentro del mismo trigger: si el movimiento deja dos
   clases del estudio en el mismo minuto, rechazar.
3. **Guard de cupo**: trigger en `clases` que rechace bajar `lugares_total` por
   debajo de las reservas activas.
4. **Borrado de grilla**: que cancele con devolución las clases con reservas en
   vez de dejarlas huérfanas (reusar la lógica de `estudio_cancelar_clase`).
5. Si se quiere "cancelar sin penalidad": marcar esas reservas para que
   `cancelar_mi_reserva` no aplique la ventana.

### 🔵 DART — build 27, mejora la experiencia pero no es lo esencial
1. **Avisar al estudio ANTES de mover**: *"Esta grilla tiene 3 alumnas
   anotadas. Si la movés, les va a cambiar el horario y les vamos a avisar.
   ¿Seguís?"*
2. Mostrar el mensaje del guard de cupo y del de colisión.
3. En "Mis reservas", destacar una clase que cambió de horario.

**Lo esencial es todo de base** ⇒ **se puede tener antes del 13/9 sin depender
del build 27.**
