#!/bin/bash
# Achica las fotos pesadas que SÍ se usan, sin cambiarles la URL y SIN perder
# la original.
#
# Por qué: cada versión liviana que sirve Supabase tiene que leer la original
# entera. Al 29/9/2026 hay 21 fotos en uso que pesan 22,8 MB entre todas, con
# originales de hasta 2,4 MB para huecos de 400 px.
#
# CÓMO ACHICA: no convierte nada en esta máquina. Le pide a Supabase la misma
# versión reducida que ya muestra la app (webp, 1600 px de ancho) y la guarda
# como nueva original. Dos motivos: es idéntica a lo que ve la usuaria, y el
# transformador NO agranda las fotos chicas — `sips` sí lo hacía, y una
# portada de 1024 px salía estirada a 1600 (encontrado el 30/9/2026 probando).
#
# LA COPIA DE SEGURIDAD: antes de pisar cada foto, la copia dentro del mismo
# bucket a `_originales/<misma ruta>`. Si la copia falla, ESA foto no se toca.
# La carpeta no la lee nadie: la app sólo mira las rutas guardadas en la base.
#
# Necesita la service key del proyecto, que Claude no puede leer. La pasás vos:
#
#   export SUPABASE_SERVICE_KEY='...'              # Dashboard → Settings → API
#   bash supabase/optimizar_fotos.sh                # prueba en seco, no toca nada
#   CONFIRMAR=1 bash supabase/optimizar_fotos.sh    # copia y reemplaza
#   RESTAURAR=1 bash supabase/optimizar_fotos.sh    # vuelve todo a las originales

set -u
PROYECTO="hvgqpzvornlnxmsbqnwg"
BUCKET="study-media"
RESPALDO="_originales"
LISTA="${LISTA:-$(dirname "$0")/fotos_pesadas_en_uso.tsv}"
ANCHO="${ANCHO:-1600}"
CALIDAD="${CALIDAD:-82}"
CONFIRMAR="${CONFIRMAR:-0}"
RESTAURAR="${RESTAURAR:-0}"

if [ -z "${SUPABASE_SERVICE_KEY:-}" ] && [ "$CONFIRMAR$RESTAURAR" != "00" ]; then
  echo "Falta SUPABASE_SERVICE_KEY. Mirá el encabezado de este archivo."
  exit 1
fi
[ -f "$LISTA" ] || { echo "No encuentro la lista: $LISTA"; exit 1; }

BASE="https://$PROYECTO.supabase.co/storage/v1"
AUTH="Authorization: Bearer ${SUPABASE_SERVICE_KEY:-sin-clave}"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# Copia server-side dentro del bucket. No baja ni sube bytes.
copiar() { # origen destino
  curl -s -o /dev/null -w "%{http_code}" -X POST "$BASE/object/copy" \
    -H "$AUTH" -H "Content-Type: application/json" \
    -d "{\"bucketId\":\"$BUCKET\",\"sourceKey\":\"$1\",\"destinationKey\":\"$2\"}"
}

# ── Volver atrás ────────────────────────────────────────────────────────────
if [ "$RESTAURAR" = "1" ]; then
  echo "Restaurando desde $RESPALDO/ ..."
  while IFS=$'\t' read -r ruta _; do
    [ -z "$ruta" ] && continue
    codigo=$(copiar "$RESPALDO/$ruta" "$ruta")
    [ "$codigo" = "200" ] && echo "  ✓ $ruta" || echo "  ✗ $ruta (HTTP $codigo)"
  done < "$LISTA"
  echo "Listo. Revisá la app y después podés borrar la carpeta $RESPALDO/."
  exit 0
fi

antes=0; despues=0; tocadas=0; saltadas=0

while IFS=$'\t' read -r ruta bytes; do
  [ -z "$ruta" ] && continue
  liviana="$TMP/liviana.webp"

  # La misma URL que usa la app, con el mismo encabezado.
  codigo=$(curl -s -o "$liviana" -w "%{http_code}" \
    -H "Accept: image/webp,image/*,*/*" \
    "$BASE/render/image/public/$BUCKET/$ruta?width=$ANCHO&resize=contain&quality=$CALIDAD")
  if [ "$codigo" != "200" ]; then
    echo "  ✗ $ruta — no pude generar la liviana (HTTP $codigo)"; saltadas=$((saltadas+1)); continue
  fi

  a="$bytes"; d=$(stat -f%z "$liviana")
  if [ "$d" -ge "$a" ]; then
    echo "  = $ruta ya está bien ($((a/1024)) kB)"; continue
  fi

  antes=$((antes+a)); despues=$((despues+d)); tocadas=$((tocadas+1))
  printf "  %s\n      %d kB → %d kB\n" "$ruta" $((a/1024)) $((d/1024))

  [ "$CONFIRMAR" = "1" ] || continue

  # 1) copia de seguridad ANTES de tocar nada
  codigo=$(copiar "$ruta" "$RESPALDO/$ruta")
  if [ "$codigo" != "200" ]; then
    echo "      ✗ no pude respaldarla (HTTP $codigo) — NO la toco"; saltadas=$((saltadas+1)); continue
  fi
  echo "      ✓ respaldada en $RESPALDO/$ruta"

  # 2) recién ahora se reemplaza
  codigo=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "$BASE/object/$BUCKET/$ruta" \
    -H "$AUTH" -H "Content-Type: image/webp" -H "x-upsert: true" \
    --data-binary "@$liviana")
  [ "$codigo" = "200" ] && echo "      ✓ reemplazada" || echo "      ✗ falló el reemplazo (HTTP $codigo) — la original sigue en $RESPALDO/"
done < "$LISTA"

echo
awk -v n="$tocadas" -v a="$antes" -v d="$despues" -v s="$saltadas" \
  'BEGIN{printf "%d fotos: %.1f MB -> %.1f MB", n, a/1e6, d/1e6; if (d>0) printf "  (%.1f veces menos)", a/d; if (s>0) printf "  |  %d saltadas", s; print ""}'
[ "$CONFIRMAR" = "1" ] || echo "Prueba en seco: no se copió ni se reemplazó nada. Para hacerlo: CONFIRMAR=1 bash $0"
