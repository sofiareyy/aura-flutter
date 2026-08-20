# Proyecto: arreglar + asegurar la promoción de lista de espera

Fecha de la nota: 2026-08-19. **Sesión dedicada** (no parchar de a pedazos).
Descubierto durante la Tanda 1 de seguridad: la promoción está ROTA, así que el
fix de seguridad de estas funciones no se puede verificar hasta arreglar la promoción.

## Estado actual: la promoción NO funciona

`waitlist_promote_next(p_clase_id, p_count)` **falla siempre** (error inmediato,
tragado por su `exception when others` → devuelve `ok:false` en silencio). Nadie
se promociona nunca → no se crean `pre_confirmada`s → `confirm_pre_reserva` y
`release_pre_reserva` no tienen sobre qué actuar.

**Dos bugs que la rompen (verificado en vivo llamándola):**
1. **`FOR UPDATE` sobre un `LEFT JOIN`** — el primer `select ... from clases c
   left join estudios e ... for update` tira `"FOR UPDATE cannot be applied to
   the nullable side of an outer join"`. Salta primero.
2. **`order by posicion` sobre columna inexistente** — `lista_espera` NO tiene
   `posicion` (columnas: id, clase_id, usuario_id **(text)**, created_at,
   notificado). El `select usuario_id, posicion ... order by posicion` fallaría
   después de arreglar el #1. También hay `update lista_espera set posicion =
   posicion - 1` que hay que sacar.

## Qué hacer en la sesión dedicada (todo junto)

1. **Arreglar el bug #1 (FOR UPDATE):** separar el lock — bloquear `clases` con
   su propio `select ... for update` sin el join a `estudios` (traer el nombre
   del estudio en un select aparte, sin `for update`).
2. **Arreglar el bug #2 (posicion → created_at):** el orden de la lista de
   espera es por **`created_at`** (orden de llegada), como se decidió (ver
   `BADGE_PACKS_pendiente.md` / auditoría item B3). Sacar toda referencia a
   `posicion` (el `order by posicion` y el `update ... set posicion`). El "puesto"
   sale del orden por `created_at`, no de una columna renumerada.
   - OJO: `lista_espera.usuario_id` es **text** (no uuid). Tenerlo en cuenta en
     los joins/comparaciones (ya se sabía del pendiente de lista de espera).
3. **Guards de seguridad (caller validation)** — el finding 🟠 de Tanda 1:
   - `waitlist_promote_next`: que un usuario cualquiera no promueva la grilla de
     una clase ajena. Permitir: admin del estudio (`es_miembro_de_estudio`), o
     un usuario con reserva en esa clase, o llamada interna. Las llamadas
     internas (desde `release_pre_reserva`) necesitan saltar el guard — usar un
     flag de sesión (`set_config('app.wl_internal','1',true)`) seteado por
     release antes de llamar a promote, y reseteado después. `revoke ... from anon`.
   - `release_pre_reserva`: solo podés liberar **tu propia** pre-reserva, **o**
     una **vencida** (para el cleanup). Guard:
     `if usuario_id is distinct from auth.uid() and not (expires_at < now()) then
     rechazar`. Esto preserva: dueño rechaza la suya (auth.uid()=usuario_id),
     cleanup libera vencidas (expired), y bloquea liberar la pre-reserva activa
     de otro. `revoke ... from anon`.
   - Único llamador interno de promote: `release_pre_reserva`. `cleanup_pre_reservas_expiradas`
     llama a release (no a promote). Revocar anon de cleanup también (defensa).
4. **Verificar end-to-end** (las dos puntas, método de siempre):
   - **Flujo legítimo:** anotarse en lista de espera → se libera un cupo (cancelo
     una reserva) → **promueve** al siguiente (crea pre_confirmada) → el promovido
     **confirma** (`confirm_pre_reserva`, ya arreglado) → paga el precio real →
     (y con el trigger de email ya puesto, al confirmarse dispara el mail al estudio).
   - **Exploit tapado:** un usuario cualquiera no puede promover una clase ajena
     ni liberar la pre-reserva de otro.

## Contexto útil
- `cancelar_mi_reserva` marca `estado='cancelada'` (no borra) y **no** promueve
  hoy — la promoción la dispara el cliente (`reservas_service.dart:387`
  `_promoverYAvisar`, y `estudio_admin_service.dart:553` al aumentar cupo).
  Evaluar si conviene mover la promoción server-side dentro de cancelar/editar.
- Cuerpos actuales: `waitlist_promote_next`, `release_pre_reserva`,
  `cleanup_pre_reservas_expiradas` están en `supabase/FIX_WAITLIST_FLOW.sql`
  (pero el desplegado es el que manda — confirmar con `pg_get_functiondef`).
