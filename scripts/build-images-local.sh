#!/bin/bash
# 在本機建置映像；請先設定 DEPLOY_ENV（預設 production）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck disable=SC1090
source "$SCRIPT_DIR/load-deploy-env.sh"

BUILD_BACKEND="${BUILD_BACKEND:-1}"
BUILD_FRONTEND="${BUILD_FRONTEND:-1}"

if ! command -v docker >/dev/null 2>&1; then
  echo "本機未安裝 Docker。請安裝 Docker Desktop 或在 WSL 內執行此腳本。" >&2
  exit 1
fi

if [ "$DEPLOY_ENV" = "production" ] && [ "$PLATFORM" != "linux/amd64" ]; then
  echo "production 上傳至 VPS 時 PLATFORM 必須為 linux/amd64（目前: $PLATFORM）" >&2
  exit 1
fi

if [ "$BUILD_BACKEND" = "1" ]; then
  echo "=== build backend: $BACKEND_IMAGE ==="
  docker build --platform "$PLATFORM" -t "$BACKEND_IMAGE" "$ROOT_DIR/Backend"
fi

if [ "$BUILD_FRONTEND" = "1" ]; then
  echo "=== build frontend: $FRONTEND_IMAGE ==="
  docker build --platform "$PLATFORM" -t "$FRONTEND_IMAGE" \
    --build-arg BASE_URL="$BASE_URL" \
    --build-arg URL_PREFIX="$URL_PREFIX" \
    --build-arg GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID" \
    --build-arg NODE_ENV=production \
    "$ROOT_DIR/Frontend"
fi

echo "BUILD_LOCAL_OK"
