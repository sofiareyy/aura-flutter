#!/bin/bash
# Achica las fotos pesadas que SÍ se usan, sin cambiarles la URL.
#
# Por qué: cada foto reducida que sirve Supabase tiene que leer la original
# entera. Al 29/9/2026 hay 21 fotos en uso que pesan 22,8 MB entre todas, con
# originales de hasta 2,4 MB para huecos de 400 px.
#
# Qué hace: baja cada foto, la reescala a 1600 px de ancho y la vuelve a subir
# AL MISMO camino, así ninguna URL guardada en la base deja de funcionar.
#
# Necesita la service key del proyecto, que Claude no puede leer. La pasás vos:
#
#   export SUPABASE_SERVICE_KEY='...'        # Dashboard → Settings → API
#   bash supabase/optimizar_fotos.sh          # muestra qué haría, no sube nada
#   CONFIRMAR=1 bash supabase/optimizar_fotos.sh   # sube de verdad
#
# Requiere `sips`, que ya viene con macOS.

set -u
PROYECTO="hvgqpzvornlnxmsbqnwg"
BUCKET="study-media"
LISTA="${LISTA:-$(dirname "$0")/fotos_pesadas_en_uso.tsv}"
ANCHO="${ANCHO:-1600}"
CALIDAD="${CALIDAD:-82}"
CONFIRMAR="${CONFIRMAR:-0}"

if [ -z "${SUPABASE_SERVICE_KEY:-}" ]; then
  echo "Falta SUPABASE_SERVICE_KEY. Mirá el encabezado de este archivo."
  exit 1
fi
[ -f "$LISTA" ] || { echo "No encuentro la lista: $LISTA"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
BASE="https://$PROYECTO.supabase.co/storage/v1"
antes_total=0; despues_total=0; tocadas=0

while IFS=$'\t' read -r ruta bytes; do
  [ -z "$ruta" ] && continue
  ext="${ruta##*.}"
  orig="$TMP/orig.$ext"
  chica="$TMP/chica.jpg"

  curl -sf -o "$orig" "$BASE/object/public/$BUCKET/$ruta" || { echo "  ✗ no pude bajar $ruta"; continue; }
  sips -Z "$ANCHO" -s format jpeg -s formatOptions "$CALIDAD" "$orig" --out "$chica" >/dev/null 2>&1 \
    || { echo "  ✗ no pude convertir $ruta"; continue; }

  a=$(stat -f%z "$orig"); d=$(stat -f%z "$chica")
  # Si la conversión no achica (ya estaba optimizada), se deja como está.
  if [ "$d" -ge "$a" ]; then
    echo "  = $ruta ya está bien ($((a/1024)) kB)"
    continue
  fi

  antes_total=$((antes_total + a)); despues_total=$((despues_total + d)); tocadas=$((tocadas + 1))
  printf "  %s  %d kB → %d kB\n" "$ruta" $((a/1024)) $((d/1024))

  if [ "$CONFIRMAR" = "1" ]; then
    codigo=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "$BASE/object/$BUCKET/$ruta" \
      -H "Authorization: Bearer $SUPABASE_SERVICE_KEY" \
      -H "Content-Type: image/jpeg" \
      -H "x-upsert: true" \
      --data-binary "@$chica")
    [ "$codigo" = "200" ] && echo "    ✓ subida" || echo "    ✗ falló la subida (HTTP $codigo)"
  fi
done < "$LISTA"

echo
awk -v n="$tocadas" -v a="$antes_total" -v d="$despues_total" 'BEGIN{printf "%d fotos: %.1f MB -> %.1f MB  (%.1fx menos)\n", n, a/1e6, d/1e6, (d>0? a/d : 0)}'
[ "$CONFIRMAR" = "1" ] || echo "Esto fue una prueba en seco. Para subir: CONFIRMAR=1 bash $0"
