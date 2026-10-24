#!/usr/bin/env bash
# Backup manual de la base de Aura (plan free de Supabase: no hay backups
# automáticos). Baja TODAS las tablas de `public` como JSON, más una foto de
# la estructura (columnas, funciones, triggers, políticas de RLS) y una lista
# mínima de cuentas de auth.users (id y mail, sin contraseñas).
#
# Uso:   ~/aura-flutter/scripts/backup_aura.sh
# Deja:  ~/OneDrive/Aura-backups/aura-AAAA-MM-DD_HHMM.tar.gz
#        (otra carpeta: AURA_BACKUP_DIR=/ruta ~/aura-flutter/scripts/backup_aura.sh)
#
# Necesita: el token de la Management API en ~/.supabase_token, curl y jq.
# El repo es público: este script no tiene claves, y los backups NUNCA van al
# repo (tienen mails y datos de cobro).

set -euo pipefail

PROYECTO="hvgqpzvornlnxmsbqnwg"
DESTINO="${AURA_BACKUP_DIR:-$HOME/OneDrive/Aura-backups}"
GUARDAR=30   # cuántos backups se conservan; los más viejos se borran
TOKEN_FILE="$HOME/.supabase_token"

[ -r "$TOKEN_FILE" ] || { echo "❌ No encuentro $TOKEN_FILE"; exit 1; }
command -v jq >/dev/null || { echo "❌ Falta jq (brew install jq)"; exit 1; }
TOKEN="$(cat "$TOKEN_FILE")"

FECHA="$(date +%Y-%m-%d_%H%M)"
TRABAJO="$(mktemp -d)"
CARPETA="$TRABAJO/aura-$FECHA"
mkdir -p "$CARPETA/tablas" "$DESTINO"
trap 'rm -rf "$TRABAJO"' EXIT

# Corre una consulta y devuelve el JSON. Reintenta si la API frena por exceso
# de pedidos; corta con error si devuelve otra cosa que una lista.
sql() {
  local intento r
  for intento in 1 2 3 4 5; do
    r="$(curl -sS -X POST "https://api.supabase.com/v1/projects/$PROYECTO/database/query" \
      -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
      -d "$(jq -n --arg q "$1" '{query:$q}')")" || r=""
    if printf '%s' "$r" | jq -e 'type == "array"' >/dev/null 2>&1; then
      printf '%s' "$r"; return 0
    fi
    sleep $((intento * 3))
  done
  echo "❌ La consulta falló: $(printf '%s' "$r" | head -c 300)" >&2
  return 1
}

echo "📦 Backup de Aura — $FECHA"

TABLAS="$(sql "select tablename from pg_tables where schemaname = 'public' order by 1" | jq -r '.[].tablename')"
TOTAL=0
: > "$CARPETA/resumen.txt"
for t in $TABLAS; do
  sql "select coalesce(json_agg(x), '[]'::json) as filas from public.\"$t\" x" \
    | jq '.[0].filas' > "$CARPETA/tablas/$t.json"
  n="$(jq 'length' "$CARPETA/tablas/$t.json")"
  TOTAL=$((TOTAL + n))
  printf '%-40s %8s filas\n' "$t" "$n" | tee -a "$CARPETA/resumen.txt"
done

# Cuentas: sólo lo necesario para volver a unir usuarios con su mail.
sql "select id, email, phone, created_at, email_confirmed_at, last_sign_in_at from auth.users order by created_at" \
  > "$CARPETA/auth_users.json"
printf '%-40s %8s filas\n' "auth.users (id y mail)" "$(jq 'length' "$CARPETA/auth_users.json")" | tee -a "$CARPETA/resumen.txt"

# Estructura: sin esto, los datos solos no alcanzan para reconstruir la base.
sql "select table_name, column_name, data_type, is_nullable, column_default
       from information_schema.columns where table_schema = 'public'
      order by table_name, ordinal_position" > "$CARPETA/estructura_columnas.json"
sql "select p.proname as nombre, pg_get_functiondef(p.oid) as definicion
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.prokind in ('f','p') order by 1" > "$CARPETA/estructura_funciones.json"
sql "select c.relname as tabla, t.tgname as nombre, pg_get_triggerdef(t.oid) as definicion
       from pg_trigger t join pg_class c on c.oid = t.tgrelid
       join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and not t.tgisinternal order by 1, 2" > "$CARPETA/estructura_triggers.json"
sql "select tablename as tabla, policyname as nombre, cmd, roles::text, qual, with_check
       from pg_policies where schemaname = 'public' order by 1, 2" > "$CARPETA/estructura_politicas.json"
sql "select jobid, jobname, schedule, active from cron.job order by jobid" > "$CARPETA/crons.json"

ARCHIVO="$DESTINO/aura-$FECHA.tar.gz"
tar -czf "$ARCHIVO" -C "$TRABAJO" "aura-$FECHA"

# Chequeo: el archivo se puede abrir y tiene todas las tablas.
EN_ARCHIVO="$(tar -tzf "$ARCHIVO" | grep -c '/tablas/.*\.json$')"
ESPERADAS="$(printf '%s\n' $TABLAS | grep -c .)"
if [ "$EN_ARCHIVO" != "$ESPERADAS" ]; then
  echo "❌ El archivo tiene $EN_ARCHIVO tablas y esperaba $ESPERADAS. No lo des por bueno."
  exit 1
fi

# Rotación: quedan los $GUARDAR más nuevos.
ls -1t "$DESTINO"/aura-*.tar.gz 2>/dev/null | tail -n +$((GUARDAR + 1)) | while read -r viejo; do
  rm -f "$viejo"
done

echo
echo "✅ Listo: $ESPERADAS tablas, $TOTAL filas, $(du -h "$ARCHIVO" | cut -f1 | tr -d ' ')"
echo "   $ARCHIVO"
echo "   Backups guardados en esa carpeta: $(ls -1 "$DESTINO"/aura-*.tar.gz | wc -l | tr -d ' ')"
