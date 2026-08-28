# 📋 Inventario completo de pendientes — 2026-08-28

Barrido de RETOMAR + los 28 archivos de la carpeta, **verificado contra la
base** (varias notas viejas ya no valían: se marcan abajo).

---

## 🟢 BASE — sale sin build

### Esperando el visto bueno del build 26
| | Qué | Nota |
|---|---|---|
| 1 | **Arreglar APNs / Firebase** | `THIRD_PARTY_AUTH_ERROR`. **Cuello de TODAS las notificaciones.** Verificado: sólo hay 3 tokens y son de la cuenta de Aura; **ninguna alumna tiene dispositivo** |
| 2 | **DROP de la columna fantasma** | `FIX_COLUMNA_FANTASMA_2026-08-26.sql`, listo sin correr |
| 3 | **Cerrar la policy temporal de nombres** | Sólo cuando los estudios **adopten** el 26, no al aprobarse |

### Los 8 menores de la auditoría fresca (re-medidos el 26/8: los 8 siguen)
| | Qué |
|---|---|
| 4 | Clase huérfana de YN Pilates (id **2439**, 31/08 11:00, 0 reservas) — decisión suya, es data real |
| 5 | **`storage.objects` sin policy DELETE** en ningún bucket: nadie puede borrar lo que sube, ni Aura |
| 6 | `admin_link_estudio_access` (fallback legacy) escribe sólo el puntero, no `estudio_admins` |
| 7 | `plan` y `subscription_status` **auto-escribibles** por la usuaria (efecto: badge falso) |
| 8 | **Las 3 RPC de bienvenida no existen** — `acreditar_bienvenida` se llama **en cada login** y falla siempre |
| 9 | `"Admins leen config"` es `using (true)`: el nombre miente. **Renombrar, no cerrar** (el gate de versión la lee antes del login) |
| 10 | `horarios_fijos` conserva `"todos pueden ver horarios"` con `using (true)` |
| 11 | 5 funciones sin `search_path` (las 5 trigger *invoker*, 0 SECURITY DEFINER) |

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
| 16 | **`crear-pago-pack` y `email-confirmacion` están en el repo y NO desplegadas** (verificado hoy) |
| 17 | `estudio_vistas` con `CHECK true`: se pueden insertar vistas sin límite |
| 18 | `study_reviews` con `using (true)` expone `usuario_id` a `anon` (bajo impacto) |
| 19 | Firma del webhook de Mercado Pago: se calcula y se descarta |
| 20 | Log de cambios de estado en `reservas` — **el 26/8 mordió**: 3 reservas desaparecieron y no se pudo saber quién |
| 21 | Salir de las keys legacy (paso 1: publicar con la nueva). Medido: la publishable **funciona** |
| 22 | `admin_upsert_estudio` **no tiene parámetro `valor_credito`** ⇒ una excepción negociada sólo se carga por SQL |
| 23 | ⏸️ **Modo gestión**: las 4 policies de `estudio_alumnos` con el mismo error de categoría que tenía `horarios_fijos`. Dormido (0 estudios en gestión) |

---

## 🔵 DART — build 27

| | Qué | De dónde sale |
|---|---|---|
| 1 | **`completada` se muestra como "Pendiente"** | El bug que la confundió el 27/8. Ojo: distinguir por `checked_in_at` |
| 2 | **Servicios de precio fijo — las 8 piezas de UI** | Chips con precio, chips de horario sin franja, renglón "precio único", pantalla del backoffice, `TipoPrecio.servicio`, cargar servicios en `_loadStudio`, mensaje de rechazo, Explorar sin badge |
| 3 | **Comisión congelada en pantalla** | Mostrar el guardado si `estado='pagado'` |
| 4 | **Pantalla de reseñas en el panel del estudio** | No existe ninguna. Los datos ya están y ya son legibles |
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
| 5 | **¿Mail de confirmación de reserva a la alumna?** | La función existe y nunca se desplegó |
| 6 | **Categorías faltantes**: Yessi (112 clases) y Ambra (77) | O que el formulario las exija |
| 7 | **Franjas de Tiwar aparentemente invertidas** (8, 9, 19, 20 en valle) | Un `admin_set_pricing_estudio`, sin recargar |
| 8 | **YN Pilates: `creditos_max` 13 sin ninguna clase ahí** | Mismo olor |
| 9 | **Estado del build 25/26 en App Store Connect** | No tengo acceso |
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
