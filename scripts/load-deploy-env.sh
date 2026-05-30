#!/bin/bash
# 依 DEPLOY_ENV 載入 deploy/env/<profile>.env（可選 local override）。
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT_DIR="$(cd "$DEPLOY_DIR/.." && pwd)"

DEPLOY_ENV="${DEPLOY_ENV:-production}"
PROFILE_FILE="$DEPLOY_DIR/env/${DEPLOY_ENV}.env"
OVERRIDE_FILE="$DEPLOY_DIR/env/${DEPLOY_ENV}.local.env"

if [ ! -f "$PROFILE_FILE" ]; then
  echo "找不到環境設定: $PROFILE_FILE" >&2
  echo "可用 DEPLOY_ENV: production" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$PROFILE_FILE"

if [ -f "$OVERRIDE_FILE" ]; then
  # shellcheck disable=SC1090
  source "$OVERRIDE_FILE"
fi

: "${PLATFORM:=linux/amd64}"
: "${BASE_URL:=}"
: "${URL_PREFIX:=}"
: "${FRONTEND_IMAGE:=mycloset-frontend:latest}"
: "${BACKEND_IMAGE:=mycloset-backend:latest}"

if [ -z "$BASE_URL" ]; then
  echo "[$DEPLOY_ENV] BASE_URL 未設定" >&2
  exit 1
fi

resolve_google_client_id() {
  if [ -n "${GOOGLE_CLIENT_ID:-}" ]; then
    return 0
  fi

  local secrets="${SECRETS_INI:-$ROOT_DIR/Backend/configs/secrets.ini}"
  if [ ! -f "$secrets" ]; then
    echo "[$DEPLOY_ENV] 請在 env 設定 GOOGLE_CLIENT_ID 或 SECRETS_INI" >&2
    exit 1
  fi

  GOOGLE_CLIENT_ID="$(grep '^client_id=' "$secrets" | cut -d= -f2-)"
  if [ -z "$GOOGLE_CLIENT_ID" ]; then
    echo "[$DEPLOY_ENV] $secrets 缺少 client_id" >&2
    exit 1
  fi
}

if [ "${BUILD_FRONTEND:-1}" = "1" ]; then
  resolve_google_client_id
fi

export DEPLOY_ENV PLATFORM BASE_URL URL_PREFIX FRONTEND_IMAGE BACKEND_IMAGE
export GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID:-}"
export SSH_HOST="${SSH_HOST:-}"
export REMOTE_DIR="${REMOTE_DIR:-/opt/deploy}"

echo "=== deploy env: $DEPLOY_ENV ==="
echo "=== platform: $PLATFORM ==="
echo "=== base url: $BASE_URL ==="
echo "=== frontend image: $FRONTEND_IMAGE ==="
echo "=== backend image: $BACKEND_IMAGE ==="
