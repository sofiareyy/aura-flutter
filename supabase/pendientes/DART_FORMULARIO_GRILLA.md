# Formulario de grilla — relevamiento y rediseño (Tanda C)

Relevado el 2026-08-25 a raíz del incidente de Tiwar (60 slots duplicados,
534 clases de más). **Es Dart ⇒ build.** No toca la base: el modelo
(`horarios_fijos`, una fila por `(día, hora)`) ya es el correcto.

## Cómo es HOY (`mis_clases_screen.dart:2000-2330`, `_openGridForm`)

Tres botones de entrada: **Nueva clase** (evento único, `_openForm`) ·
**Nuevo workshop / experiencia** · **Crear grilla** (`_openGridForm`).

El sheet "Nueva grilla" muestra, en orden:
1. Un párrafo: *"Esto crea muchos horarios fijos de una sola vez. Las clases se
   van a programar automáticamente para los próximos 3 meses…"* (dice 3 meses;
   `kGrillaSemanas = 9` ⇒ ~2 meses. Corregir el texto.)
2. **Nombre de la clase** (hint "Yoga restaurativo").
3. **Días**: chips L–D, **L–V preseleccionados**.
4. **Desde** (default **07:00**) y **Hasta** (default **21:00**): dos campos
   con `showTimePicker`.
5. **Duración de cada clase**: dropdown 30/45/60/75/90. ⚠️ Es también el
   **paso** del generador, y nada lo dice.
6. Campos extra plegados (profe, cupos, créditos, categorías…).

Cartel de confirmación ("Revisá antes de generar"): *"Vas a generar 585
clases · Desde el 25 de agosto hasta el 27 de octubre · 13 clases por día de
1 h, entre 08:30 y 21:30 · Si ya había clases en esos horarios no se
duplican"* → **[Volver] [Generar 585]**.

Generación (`crearHorariosFijosEnGrilla`, `estudio_admin_service.dart:452`):
un horario fijo por cada `duración` minutos entre Desde y Hasta, por cada día
elegido; después `generarProximasSemanasDesdeHorarios()` publica 9 semanas.

## Por qué Tiwar creyó que cargaba 2 y cargó 13 (× 5 días, × 2 veces)

1. **No hay herramienta para "una clase semanal a las 8:30".** "Nueva clase"
   es un evento único; la única forma de que algo se repita todas las semanas
   es "Crear grilla", que es un generador por rango. Un estudio con 2 clases
   por día **está obligado** a usar un formulario pensado para 12.
2. **"Desde / Hasta" se lee como horario de apertura**, no como "generá una
   clase cada 60 min entre estas dos horas". Tiwar puso Desde 08:30 (su
   primera clase) y Hasta 21:30 (cierra el gym). Es una lectura razonable del
   label. La segunda vez, Desde 09:30 / Hasta 22:30: lo mismo.
3. **El paso está escondido en "Duración de cada clase".** Nadie deduce que
   60 min de duración significa una clase por hora.
4. **La confirmación da números, no la lista.** "13 clases por día … Generar
   585" es abstracto; **nunca ve "08:30, 09:30, 10:30, 11:30…"**. Con la lista a
   la vista se frena solo.
5. Después no se ve el error: a las 16:15 las clases de 08:30 y 09:30 de ese
   día ya pasaron y no aparecen en "Próximas"; lo primero que ve son las de
   16:30 en adelante (y en reloj de 12 h, item 20).

## Opciones evaluadas

| | Qué | Contra |
|---|---|---|
| A · solo horarios puntuales | marcar 08:30, 09:30, uno por uno | Citra/Yessi tienen 23 grillas; Sculpt 17. Tipear 12 horas × 6 días es fricción real. El rango sirve |
| B · el rango, pero con la lista completa antes de confirmar | mismo form, mejor preview | La confusión nace **antes**, en "Desde/Hasta"; el preview la atrapa tarde y con 13 items para leer. Mejor que hoy, pero conserva el modelo mental equivocado |
| C · dos modos (puntuales / rango) | correcto | un switch más que decidir, y "¿en qué modo estoy?" es una confusión nueva |

## Recomendación: **lista primero, rango como atajo** (C sin el switch)

**La lista de horarios es lo único que se envía, y es la vista previa.** No hay
modo: el estudio siempre está mirando la lista exacta de lo que va a crear.

```
Nombre de la clase       [Crossfit / Hyrox        ]
Días                     (L)(M)(X)(J)(V)( S )( D )
Duración de cada clase   [60 min ▾]

Horarios                                    ← la lista, ordenada, chips con ×
  [08:30 ×] [09:30 ×]
  + Agregar horario        ← time picker (24 h), agrega UN chip
  Completar un rango…      ← atajo: Desde / Hasta / cada [60 min]
                              → RELLENA la lista con chips; no envía nada

─────────────────────────────────────────────
Revisá antes de crear
  Lun, Mar, Mié, Jue, Vie · 08:30, 09:30
  10 horarios fijos · 90 clases en las próximas 9 semanas
                                 [Volver]  [Crear 10 horarios]
```

**Por qué esta y no otra:**
- **Elimina la confusión en el origen:** ya no existe un campo "Hasta" que se
  pueda leer como hora de cierre. Si querés 13 clases por día, tenés que ver
  13 chips antes de apretar.
- **Cubre a los dos tipos de estudio sin elegir modo:** Rock Studio agrega
  07:00, 08:00, 09:00, 19:00 a mano (4 chips); Citra usa "Completar un rango"
  y le aparecen sus 12 chips, que puede podar.
- **Es lo más simple de construir que resuelve el problema.** El modelo de
  datos no cambia; `crearHorariosFijosEnGrilla` ya arma `rows` a partir de
  `(día, hora)`; sólo cambia la firma: `List<TimeOfDay> horarios` en vez de
  `horaInicio/horaFin`. Es UI dentro de `_openGridForm` +
  `_confirmarGeneracionGrilla` + una firma de servicio. Nada de base.
- **El guard del 25/8 (`trg_horarios_fijos_00_sin_duplicados`) es la red:**
  aunque manden el mismo lote dos veces, se rechaza con mensaje legible.

**Detalles que van con esto:**
- Chips y picker en **24 h** (item 20: la tarjeta del panel también).
- `Duración` deja de ser el paso: el paso vive en el atajo ("cada X min",
  default = duración) y la duración es sólo la duración.
- Sin horarios en la lista ⇒ botón deshabilitado. Sin días ⇒ idem.
- La confirmación lista **días + horarios**, no "N por día entre X e Y".
- El snackbar usa lo que devuelve el servidor, no `rows.length` (item 21).
- Corregir el párrafo de arriba: "próximas 9 semanas", no "3 meses".
- **Misma lista para todos los días elegidos.** Si un estudio tiene horarios
  distintos por día, corre el form dos veces (el guard evita duplicados).
  Horarios por día es una v2, no hace falta ahora.
- El helper "Completar un rango" hereda validaciones que ya existen
  (`fin > inicio`, `franjasPorDia > 0`).
