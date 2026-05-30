#!/bin/bash
# 將本機映像 docker save → scp → docker load；需 DEPLOY_ENV=production。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck disable=SC1090
source "$SCRIPT_DIR/load-deploy-env.sh"

if [ "$DEPLOY_ENV" != "production" ]; then
  echo "sync-images-to-server 僅供 production；本機測試請直接 docker compose up" >&2
  exit 1
fi

if [ -z "${SSH_HOST:-}" ]; then
  echo "[$DEPLOY_ENV] SSH_HOST 未設定" >&2
  exit 1
fi

SYNC_FRONTEND="${SYNC_FRONTEND:-1}"
SYNC_BACKEND="${SYNC_BACKEND:-1}"
TMP_DIR="${TMP_DIR:-/tmp/mycloset-images}"

mkdir -p "$TMP_DIR"

pack_and_upload() {
  local image="$1"
  local name="$2"
  local tar="$TMP_DIR/${name}.tar.gz"

  echo "=== pack $image ==="
  docker save "$image" | gzip > "$tar"
  echo "=== upload $(basename "$tar") → $SSH_HOST:$REMOTE_DIR/ ==="
  scp -o BatchMode=yes "$tar" "${SSH_HOST}:${REMOTE_DIR}/${name}.tar.gz"
  rm -f "$tar"
}

REMOTE_CMD="set -euo pipefail; cd $REMOTE_DIR"

if [ "$SYNC_BACKEND" = "1" ]; then
  if ! docker image inspect "$BACKEND_IMAGE" >/dev/null 2>&1; then
    echo "本機找不到映像: $BACKEND_IMAGE" >&2
    exit 1
  fi
  pack_and_upload "$BACKEND_IMAGE" "backend-image"
  REMOTE_CMD="$REMOTE_CMD; gunzip -c backend-image.tar.gz | docker load; rm -f backend-image.tar.gz"
fi

if [ "$SYNC_FRONTEND" = "1" ]; then
  if ! docker image inspect "$FRONTEND_IMAGE" >/dev/null 2>&1; then
    echo "本機找不到映像: $FRONTEND_IMAGE" >&2
    exit 1
  fi
  pack_and_upload "$FRONTEND_IMAGE" "frontend-image"
  REMOTE_CMD="$REMOTE_CMD; gunzip -c frontend-image.tar.gz | docker load; rm -f frontend-image.tar.gz"
fi

if [ "$SYNC_BACKEND" = "1" ] || [ "$SYNC_FRONTEND" = "1" ]; then
  REMOTE_CMD="$REMOTE_CMD; docker compose up -d"
  [ "$SYNC_BACKEND" = "1" ] && REMOTE_CMD="$REMOTE_CMD backend"
  [ "$SYNC_FRONTEND" = "1" ] && REMOTE_CMD="$REMOTE_CMD frontend"
  REMOTE_CMD="$REMOTE_CMD; docker compose ps; echo SYNC_OK"
fi

echo "=== apply on $SSH_HOST ==="
ssh -o BatchMode=yes "$SSH_HOST" "$REMOTE_CMD"

echo "SYNC_IMAGES_OK"
