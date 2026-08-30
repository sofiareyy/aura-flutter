# 📋 Inventario completo de pendientes — 2026-08-28

Barrido de RETOMAR + los 28 archivos de la carpeta, **verificado contra la
base** (varias notas viejas ya no valían: se marcan abajo).

---

## 🟢 BASE — sale sin build

### Esperando el visto bueno del build 26
| | Qué | Nota |
|---|---|---|
| 1 | ✅ **ARREGLADO 29/8** · la credencial en Firebase estaba como "de desarrollo" y la app manda tokens de producción (verificado en el `.ipa`: `aps-environment=production`). Re-subida el `.p8` como Auth Key → `enviados: 3 · fallidos: 0`. Todas las notificaciones cableadas quedaron vivas |
| 2 | ✅ **HECHO 29/8** · dropeada con el 26 confirmado en la tienda; 0 valores re-medidos antes; smoke de lectura y reserva OK |
| 3 | **Cerrar la policy temporal de nombres** | Sólo cuando los estudios **adopten** el 26, no al aprobarse. Al 30/8: **4 en 🔴** (Citra, Sculpt, Ambra, Barre); YN Pilates ya está ✅. El force-update los va empujando solo |

### Los 8 menores de la auditoría fresca (re-medidos el 26/8: los 8 siguen)
| | Qué |
|---|---|
| 4 | ✅ **HECHO 28/8** · huérfana 2439 borrada. Pre-chequeadas las 4 FK: 0 reservas, 0 lista de espera, 0 reseñas, 0 avisos. La gemela de grilla (2441) sigue: queda 1 clase en ese horario |
| 5 | ✅ **HECHO 28/8** · policies DELETE en los 3 buckets (cada quien su carpeta) + superadmin en todos. Probado por la Storage API: borra lo suyo, 403 a lo ajeno |
| 6 | ✅ **HECHO 28/8** · decisión: NO borrarla (el backoffice la tiene como fallback vivo), hacerla consistente. Ahora escribe también `estudio_admins` con el mismo insert acumulativo de `studio_promote_user_to_admin`. Idempotente, medida en 3 puntas |
| 7 | ✅ **HECHO 28/8** · eran **4** columnas libres (+`mp_subscription_id`, `renewal_date`), cerradas en el guard. El webhook (service_role) sigue pasando |
| 8 | ✅ **DECIDIDO 29/8: descartado por ahora** — no se regalan créditos a usuarios nuevos. ⇒ borrar las 3 llamadas del Dart va al **build 27** (saca la RPC fallida de cada login) |
| 9 | ✅ **HECHO 28/8** · renombrada a "config global: lectura publica (la lee el gate de version pre-login)" — sigue abierta a propósito |
| 10 | ✅ **HECHO 28/8** · dropeada. Quedan las 4 por `es_miembro_de_estudio`: el estudio ve las suyas, otro estudio y las alumnas 0 (medido) |
| 11 | ✅ **HECHO 28/8** · las 5 con `search_path=public`. Quedan **0** funciones sin search_path en todo public |

### Features con diseño cerrado, falta construir
| | Qué |
|---|---|
| 12 | ✅ **HECHO 28/8 · Comisión congelada** (`FEAT_COMISION_CONGELADA_2026-08-28.sql`) — falta sólo el Dart de pantalla (build 27) |
| 13 | ✅ **HECHO 28/8 · Aviso de reseña al estudio** — campanita + mail (`resena-email`); editar no re-spamea |
| 14 | 🔴 **UNIQUE de reseñas: BLOQUEADO para base-sola, va al build 27.** Medido: el upsert de la app instalada usa `on conflict (estudio_id, usuario_id)` y con el índice nuevo da 42P10 ⇒ rompería crear/editar reseñas. Base + Dart (`onConflict` nuevo + pasar `claseId`) juntos, con adopción |
| 15 | ✅ **HECHO 28/8 · Pedido de reseña post-clase** — cron `pedir-resenas-15min`, sólo a quien asistió, dedup por `resena_pedida_at` |

### Deuda que nadie está mirando
| | Qué |
|---|---|
| 16 | 🟡 **`email-confirmacion`: HECHA 29/8** — refactorizada al patrón de secreto + trigger en base (`trg_notif_email_confirmacion_alumna`), texto aprobado por la usuaria, activa para todas. Dispara SOLO en INSERT confirmada y pre→confirmada (el deshacer check-in NO re-manda, medido). ✅ **`crear-pago-pack` BORRADA el 30/8** — era código muerto (0 referencias en `lib/` y `web/`; el camino vivo es `crear-checkout-pack` v56). Se fueron los 3 archivos y su bloque de `config.toml` |
| 17 | ✅ **HECHO 29/8** · la vista es tuya (`usuario_id = auth.uid()`) y máx. 1 por estudio por hora, vía helper SECURITY DEFINER (`vista_reciente`; un `not exists` directo en el check corría bajo RLS y veía 0 filas — medido). Spoofear rechazado; otro estudio en la misma hora entra |
| 18 | 🔴 **NO es base-only → build 27.** La mecánica correcta es revoke de tabla + grant por columnas (el revoke por columna sola es no-op si hay grant de tabla — medido). PERO `reviews_service.dart` pide `usuario_id` explícito y el invitado carga reseñas sin try/catch ⇒ aplicarlo hoy rompe el detalle de estudio en modo visita. Va junto al cambio de `select` del Dart |
| 19 | ⏸️ **Decisión 29/8: NO tocar por ahora.** Mitigado (verifica contra la API de MP después). Es segunda capa opcional; reforzar cuando haya volumen. No tocar el camino de pagos con plata real sin necesidad |
| 20 | ✅ **HECHO 29/8** · `reservas_estado_log` + trigger: registra CREADA, cada ESTADO y BORRADA (el caso del 26/8 fue un DELETE), con quién (`auth.uid()`) y como qué rol. **Sin FKs a propósito**: la historia sobrevive a la reserva/clase/usuaria. RLS sin policies: cero acceso desde el cliente (verificado). Viaje completo medido |
| 21 | Salir de las keys legacy (paso 1: publicar con la nueva). Medido: la publishable **funciona** |
| 22 | ✅ **HECHO 29/8** · `p_valor_credito` con default -1 (=no tocar; null=seguir global; >0=negociado). La firma vieja se DROPeó antes de recrear (dos firmas = PGRST203 y el backoffice roto). Medido: llamada vieja no pisa, 1500 fija, null limpia, 0 rechazado |
| 23 | ⏸️ **Modo gestión**: las 4 policies de `estudio_alumnos` con el mismo error de categoría que tenía `horarios_fijos`. Dormido (0 estudios en gestión) |

---

## 🔵 DART — build 27

| | Qué | De dónde sale |
|---|---|---|
| 1 | **`completada` se muestra como "Pendiente"** | El bug que la confundió el 27/8. Ojo: distinguir por `checked_in_at` |
| 2 | **Servicios de precio fijo — las 8 piezas de UI** · 🟡 **piezas 1–3 HECHAS 30/8** (`PricingCalculator` 974/974 contra la base · chips `Sauna · 14 cr` · renglón "precio único" en la grilla) | Faltan: pantalla del backoffice, snackbar de rechazo al guardar, Explorar sin badge |
| 3 | **Comisión congelada en pantalla** | Mostrar el guardado si `estado='pagado'` |
| 4 | **Pantalla de reseñas en el panel del estudio** | No existe ninguna. Los datos ya están y ya son legibles. **Diseño de la tarjeta ya decidido (28/8)**: nombre izq + estrellas der arriba · clase y fecha en itálica · texto abajo. Ver `COMISION_CONGELADA_y_RESENAS.md` |
| 5 | **Clase + fecha en cada reseña** | *"Juanita · Barre · 27 ago 2026"* |
| 6 | **Pasar `claseId` al dejar reseña** | El service ya lo acepta; quien lo llama no se lo pasa |
| 7 | **Notificación de reseña**: offset +2h → +15min, tap a dejar reseña, y que ande en web | Hoy es local y va a `/estudio/:id` |
| 8 | Badge "MEJOR VALOR" de packs (base + Dart) | Quedó fuera del 26 por decisión suya |
| 9 | `ITSAppUsesNonExemptEncryption` en el Info.plist | Evita la pregunta de encriptación en cada subida |
| 10 | Launch image: sigue el placeholder de Flutter | No bloquea, pero es lo primero que se ve |
| 11 | OAuth duplicado en las pantallas de auth | Deuda de refactor |
| 12 | Premio 50 clases — Fase B (canje real) | |
| 13 | Devoluciones / cancelación flexible | `BUILD22_cancelacion_flexible.md` |
| 14 | "Excepción de la serie", "pausar un horario", filtro de canceladas viejas | Salieron de la revisión del formulario de grilla |

---

## 🟠 NEGOCIO / CONVERSACIÓN — las seguís vos

| | Qué | Cuándo |
|---|---|---|
| 1 | 🔴 **Qué pasa con las anotadas cuando el estudio mueve una grilla** | **Antes del 13/9.** Hoy no muerde (0 clases de grilla con reservas), pero con reservas reales sí |
| 2 | **Avisar el fin de la gracia** | **Citra el 13/9**, 6 estudios hasta el 30/9 |
| 3 | **`admin_delete_estudio` destruye la facturación del estudio** | Charla con la contadora: ¿archivar o borrar? |
| 4 | **Archivar clases viejas** | Misma charla |
| 5 | ✅ **RESUELTO** — mail de confirmación **decidido, desplegado y activo desde el 29/8**. Cableado por base (trigger), texto aprobado. Le llega a todas las alumnas | |
| 6 | **Categorías faltantes**: Yessi (112 clases) y Ambra (77) | O que el formulario las exija |
| 7 | **Franjas de Tiwar aparentemente invertidas** (8, 9, 19, 20 en valle) | Un `admin_set_pricing_estudio`, sin recargar |
| 8 | **YN Pilates: `creditos_max` 13 sin ninguna clase ahí** | Mismo olor |
| 9 | ✅ **RESUELTO 30/8** — Sofía confirmó que **los builds 25 y 26 están publicados**. Cierra 8 días de "estado desconocido" en `BUILD_IOS_pendiente.md` | |
| 10 | ⏭️ **Tanda B — verificación de mail** | Salteada hasta la primera empresa |
| 11 | **Sanear los docs de esta carpeta** + escribir el doc de eventos gratis | `SANEAR_ESTOS_DOCS.md` |

---

## ⚠️ Notas VIEJAS que ya no valen (verificado hoy contra la base)

- `SEPARAR_DATOS_COBRO.md` dice que `waitlist_count_public` sigue abierta:
  **ya no existe** (0 policies con ese nombre).
- `POST_AUDITORIA_2026-08-21.md` menciona `pack_credits_expiration` con 3
  overloads: **la función ya no existe**.
- El mismo archivo da la foto de perfil como rota: **anda** (hay un avatar
  subido el 24/8, y el 26/8 se unificaron los dos caminos de upload).
- `PRESERVAR_FACTURACION.md` (21/8) quedó reemplazado por
  `PRESERVAR_FACTURACION_plan.md` + lo aplicado el 26/8.
