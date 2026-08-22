# Pendientes de Dart para el próximo build

Anotado el 2026-08-22. Son todos cambios de app (necesitan build). Web sale al
pushear a `main`; mobile espera la tienda. Conviene mandarlos juntos.

Ninguno bloquea nada: la protección de precios ya está cerrada del lado base
(migraciones `20260822140000` y `20260822150000`).

---

## 1. El mensaje de "falta configurar el precio" no llega en el alta

**Dónde:** `lib/screens/clases/mis_clases_screen.dart:1975` — el `catch` de
`_openForm` (alta de clase individual y edición de horario fijo).

**Qué pasa:** desde la migración `20260822150000`, un estudio sin precio
configurado recibe del servidor un mensaje pensado para que lo lea una
persona:

> Falta configurar el precio de este estudio para poder cargar clases.
> Escribinos y lo activamos.

Ese `catch` lo descarta y muestra `'No se pudo crear la clase. Intentá de
nuevo.'`. Genérico, y encima invita a reintentar para siempre.

**Qué hacer:** propagar el mensaje del servidor cuando venga de un
`PostgrestException`, igual que ya hace `_editClaseDialog` en la línea 1010
(`'No se pudo guardar: ${e.message}'`). Ese camino sí lo muestra bien hoy.

**Mitigación mientras tanto:** configurar el precio del estudio ANTES de darle
el acceso. Con ese orden nadie llega a ver el mensaje.

---

## 2. El badge "PRECIO REDUCIDO" aparece en casi todas las clases

**Dónde:** `lib/screens/explorar/explorar_screen.dart:1009`.

**Qué pasa:** la condición es `tipoPrecio == 'normal' || tipoPrecio ==
'valle'`, y `'normal'` es lo que devuelve el modo de precio fijo. Con 8 de 9
estudios en modo fijo, **578 de 589 clases futuras muestran el cartel verde de
rebaja**. Un badge que aparece en el 98% de los casos no significa nada — y
justo ahora que se está vendiendo pico/valle, el argumento de "hay horarios
más baratos" se apoya en ese cartel.

Peor: en Sculpt las clases de 16 créditos con etiqueta vencida salen
anunciadas como oferta.

**Qué hacer:** que el badge verde salga sólo con `tipo_precio == 'valle'`.

---

## 3. "Ver todas" de Experiencias lleva a donde no hay ninguna

**Dónde:** `lib/screens/home/home_screen.dart:768`.

**Qué pasa:** el carrusel "EXPERIENCIAS" del home tiene un "Ver todas" que
navega a `/explorar`, que es exactamente la pantalla que las excluye a
propósito (`clases_service.dart:23`, `.neq('tipo','workshop')`).

**Qué hacer:** apuntar a un destino que exista. Definitivo cuando esté la
pestaña de Experiencias en Explorar; provisorio, sacarlo.

---

## 4. Los ceros de las clases gratis

**Dónde:** `detalle_clase_screen.dart` (bloque de precio, botón),
`confirmar_reserva_screen.dart` (fila de costo y botón), y las tres cards
(`explorar_screen.dart:1059`, `clase_card.dart:179`,
`home_screen.dart:1915`).

**Qué pasa:** una clase de 0 créditos no dice "gratis" en ningún lado. Dice
cero: `0 cr` en las cards, `0 créditos` en el detalle, `Reservar · 0 créditos`,
y al final `Canjear · 0 créditos`, que suena a error.

**Cuándo:** cuando exista la primera clase gratis. Hoy hay 0 en la base, y las
clases gratis recurrentes siguen siendo imposibles hasta que esté la excepción
del Modelo C. Las experiencias gratis sí se pueden cargar ya.

**Ojo:** el `'Reservar gratis'` que ya existe en `detalle_clase_screen.dart:1230`
NO sirve para esto — depende de `_esGratuita`, que significa "sos alumno de
este estudio en modo gestión", por usuario y no por clase. Son dos "gratis"
distintos y hay que decidir cuál gana.
