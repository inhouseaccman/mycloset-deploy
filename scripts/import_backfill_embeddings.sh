#!/bin/bash
set -euo pipefail

SQL_FILE="${1:-/tmp/backfill_embeddings.sql}"
REMOTE_DIR="${REMOTE_DIR:-/opt/deploy}"

[ -f "$SQL_FILE" ] || { echo "missing SQL file: $SQL_FILE" >&2; exit 1; }

set -a
# shellcheck disable=SC1091
source "$REMOTE_DIR/.env"
set +a

docker compose -f "$REMOTE_DIR/docker-compose.yml" exec -T db \
  mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" < "$SQL_FILE"

docker compose -f "$REMOTE_DIR/docker-compose.yml" exec -T db \
  mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -N -e \
  "SELECT COUNT(*) FROM clothing_item_images WHERE embedding IS NOT NULL;"

echo "BACKFILL_IMPORT_OK"
