# Pendiente: Fase B — canje real del premio de 50 clases (10% off en experiencia)

Fecha de la nota: 2026-08-19. Requiere base (columna/registro + checkout). No urgente
(nadie llega a 50 clases por un buen rato). La Fase A (barra hacia 50 + premio como
meta, solo visual, Dart) se hace ahora sin tocar la base.

## Qué es

Cuando un usuario llega a **50 clases tomadas** (reservas con estado
`presente`/`completada`), gana **10% de descuento en UNA experiencia**, por única vez.

## 🔑 Decisión de negocio (simplifica el diseño)

**El 10% de descuento lo absorbe AURA de su comisión, NO el estudio.**
- En experiencias, Aura se lleva **15%** (`comision_workshop`, ver `Liquidacion`).
- Cuando se aplica el premio: **Aura se lleva 5%** y el **estudio cobra exactamente
  igual que siempre**.
- O sea: el estudio **no se entera ni resigna nada** — el descuento sale del margen
  de Aura (15% → 5%). No hay que avisarle ni negociar con el estudio.

Esto evita tener que tocar la liquidación del estudio: el precio que paga el usuario
baja 10%, el estudio recibe su parte normal, y Aura se queda con menos comisión.

## Qué construir (cuando haya token)

1. **Registrar que lo ganó y si ya lo usó** — lo más simple: una columna en `usuarios`
   tipo `premio_50_usado boolean default false` (o una tabla `recompensas` si se quiere
   histórico). El "ganó" se deriva del contador (≥50); lo que hay que persistir es el
   **"ya lo usó"** para no repetir.
2. **Aplicar el 10% en el checkout de experiencias** (una sola vez):
   - Elegible si: clases_tomadas ≥ 50 **y** `premio_50_usado = false` **y** la compra es
     de una **experiencia**.
   - El precio al usuario baja 10%; la liquidación del estudio se calcula **sin** el
     descuento (recibe lo de siempre); Aura absorbe la diferencia (comisión 15% → ~5%).
   - Marcar `premio_50_usado = true` de forma **atómica** en el mismo flujo (para que
     no se aplique dos veces — mismo cuidado de idempotencia que los pagos).
3. **UI de canje**: cuando esté elegible, ofrecer el descuento en el checkout de la
   experiencia (y actualizar el badge del Perfil de "meta" a "canjeado").

## Verificación (cuando se construya)
- Elegible (≥50, no usado) compra experiencia → paga 10% menos, estudio cobra normal,
  Aura ~5%, y `premio_50_usado` queda en true.
- Segundo intento → ya no elegible (no se repite).
- Usuario con <50 → no elegible.
