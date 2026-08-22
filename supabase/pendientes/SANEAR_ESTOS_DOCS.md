# Pendiente: sanear esta carpeta — cabecera de ESTADO + FECHA en cada doc

**ESTADO:** abierto · **Verificado contra la base:** 2026-08-21

Sesión dedicada, no mezclar con otra tarea. Es trabajo de documentación: no
toca base ni código.

## El problema

Los docs mezclan lo hecho con lo pendiente y no dicen cuándo se verificaron por
última vez. **El 2026-08-21 eso costó tiempo cuatro veces**: se arrancó a
"arreglar" cosas que ya estaban resueltas, y hubo que medir contra la base para
darse cuenta.

| # | Qué decía el doc | Qué pasaba de verdad |
|---|---|---|
| 1 | `AUDITORIA_SEGURIDAD_2026-08-20.md`: tabla de 8 funciones "🟡 ABIERTOS" | **7 de 8 ya cerradas.** Ninguna alcanzable por anon ni authenticated |
| 2 | `BUILD_IOS_pendiente.md`: "la pantalla de lista de espera está rota" | arreglado en la Tanda 2 (`d70debf`) |
| 3 | `AUDITORIA_pre_android.md` punto 7: "el switch de bienvenida revienta" | protegido en dos capas; no revienta |
| 4 | `POST_AUDITORIA_2026-08-21.md`: el bug del vencimiento de packs "está vivo hoy" | el mecanismo era real pero **no alcanzable**: no existe pantalla para editar packs |

En los cuatro casos, la única forma de saberlo fue **medir contra la base**, no
releer el doc.

## Qué hacer

Ponerle a **cada** `.md` de esta carpeta una cabecera en la primera línea
después del título:

```markdown
# Título del pendiente

**ESTADO:** abierto | cerrado | parcial · **Verificado contra la base:** YYYY-MM-DD
```

Reglas:

- **abierto** — nada hecho, o hecho a medias y sin verificar.
- **parcial** — parte aplicada y verificada, parte no. Decir cuál es cuál.
- **cerrado** — verificado contra la base/código, con la medición que lo prueba.
  Se deja el doc (sirve de historia) pero con la cabecera clara.
- La **fecha es de verificación, no de escritura**. Un doc escrito el 19 y
  verificado el 21 lleva el 21.
- Si un doc mezcla partes cerradas y abiertas, marcar **cada sección** con su
  propio ✅ / ⏳, como se hizo con el punto 7 de `AUDITORIA_pre_android.md`.

## Punto de partida — estado conocido al 2026-08-21

Esto ya está medido, no hay que re-investigarlo:

| Doc | Estado probable | Nota |
|---|---|---|
| `AUDITORIA_SEGURIDAD_2026-08-20.md` | **parcial** | la tabla de "abiertos" está 7/8 cerrada; queda `ensure_referral_code` sin `search_path` |
| `AUDITORIA_pre_android.md` | **parcial** | punto 7 ya marcado cerrado; revisar 1-6 y 8-9 |
| `BUILD_IOS_pendiente.md` | **parcial** | lista de espera ya resuelta; el 25 quedó en "en preparación" y hay que pasarlo a subido |
| `PUSH_NOTIFICACIONES.md` | **cerrado** | dice "PLANIFICADO"; está implementado y salió en el build 25 |
| `MODO_VISITA_pieza_A.md` | **parcial** | A y B completas; falta la Pieza C |
| `SEPARAR_DATOS_COBRO.md` | **cerrado** | dice "EN EJECUCIÓN"; está aplicado |
| `LISTA_ESPERA_arreglar_y_asegurar.md` | **parcial** | Tandas 1 y 2 hechas; quedan 2 puntos de UI |
| `EMAIL_ESTUDIO_RESERVA.md` | **cerrado** | la edge function existe y está desplegada |
| `POST_AUDITORIA_2026-08-21.md` | **parcial** | ya tiene una sección de cerrados; mantenerla |
| `FARMEO_VENCIMIENTO_CANCELACION.md` | **abierto** | 🔴 lo primero de la próxima sesión |
| `PRESERVAR_FACTURACION.md` | **abierto** | |
| `SALIR_DE_KEYS_LEGACY.md` | **abierto** | |
| `WHITELIST_ESTADOS_ESTUDIO.md` | **abierto** | |
| `CORREO_SALIENTE.md` | **abierto** | |
| `DART_FOTO_PERFIL.md` | **abierto** | la parte de base ya se cerró |
| `BUILD22_cancelacion_flexible.md` | **abierto** | se solapa con `FARMEO_...`; revisar si conviene fusionarlos |
| `BADGE_PACKS_pendiente.md` | **abierto** | |
| `PREMIO_50_CLASES_faseB.md` | **abierto** | |
| `REFACTOR_oauth_duplicado.md` | **abierto** | |
| `LIMPIAR_sql_sueltos_generar_clases.md` | **abierto** | |
| `VERIFICACION_MAIL_Y_LOGIN.md` | **revisar** | se solapa con la sección de verificación de mail de `POST_AUDITORIA` |

Son **21 docs**. La tabla de arriba es un punto de partida, **no un veredicto**:
cada uno hay que confirmarlo midiendo antes de ponerle la cabecera. Ese es
justamente el punto del ejercicio.

## Extra, si sobra tiempo

- **Fusionar los que se solapan**: `BUILD22_cancelacion_flexible` con
  `FARMEO_VENCIMIENTO_CANCELACION`, y `VERIFICACION_MAIL_Y_LOGIN` con la
  sección de mail de `POST_AUDITORIA_2026-08-21`.
- **Un `LEEME.md` índice** en la carpeta, con los abiertos ordenados por
  prioridad, para no tener que abrir 21 archivos.
