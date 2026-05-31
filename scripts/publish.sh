#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$DEPLOY_DIR/.." && pwd)"

DEPLOY_ENV="${DEPLOY_ENV:-production}"
PROFILE="$DEPLOY_DIR/env/${DEPLOY_ENV}.env"
LOCAL="$DEPLOY_DIR/env/${DEPLOY_ENV}.local.env"

[ -f "$PROFILE" ] || { echo "missing $PROFILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$PROFILE"
[ -f "$LOCAL" ] && source "$LOCAL"

: "${PLATFORM:=linux/amd64}"
: "${GIT_BRANCH:=master}"
: "${REMOTE_DIR:=/opt/deploy}"
: "${BUILD_REMOTE_DIR:=/opt/build/closet-management}"
: "${FRONTEND_IMAGE:=mycloset-frontend:latest}"
: "${BACKEND_IMAGE:=mycloset-backend:latest}"
: "${BACKEND_REPO:=https://github.com/inhouseaccman/mycloset-backend.git}"
: "${FRONTEND_REPO:=https://github.com/inhouseaccman/mycloset-frontend.git}"
: "${DEPLOY_REPO:=https://github.com/inhouseaccman/mycloset-deploy.git}"
: "${SSH_CONFIG_BUILD:=$ROOT_DIR/.ssh/config}"

BUILD_BACKEND="${BUILD_BACKEND:-1}"
BUILD_FRONTEND="${BUILD_FRONTEND:-1}"
BUILD_MANAGEMENT="${BUILD_MANAGEMENT:-1}"
SYNC_BACKEND="${SYNC_BACKEND:-1}"
SYNC_FRONTEND="${SYNC_FRONTEND:-1}"
PRUNE_VPS_IMAGES="${PRUNE_VPS_IMAGES:-1}"

[ -n "${BASE_URL:-}" ] || { echo "BASE_URL required" >&2; exit 1; }
[ -n "${BUILD_SSH_HOST:-}" ] || { echo "BUILD_SSH_HOST required" >&2; exit 1; }
[ -n "${SSH_HOST:-}" ] || { echo "SSH_HOST required" >&2; exit 1; }
[ -f "$SSH_CONFIG_BUILD" ] || { echo "missing $SSH_CONFIG_BUILD" >&2; exit 1; }
[ "$PLATFORM" = "linux/amd64" ] || { echo "PLATFORM must be linux/amd64" >&2; exit 1; }
[ "$BUILD_FRONTEND" != "1" ] || [ -n "${GOOGLE_CLIENT_ID:-}" ] || { echo "GOOGLE_CLIENT_ID required" >&2; exit 1; }

# shellcheck disable=SC1090
source "$SCRIPT_DIR/lib.sh"

[ "$BUILD_MANAGEMENT" != "1" ] || bash "$SCRIPT_DIR/build-management.sh"

export BUILD_BACKEND BUILD_FRONTEND SYNC_BACKEND SYNC_FRONTEND
export PLATFORM BASE_URL URL_PREFIX GOOGLE_CLIENT_ID
export BACKEND_IMAGE FRONTEND_IMAGE BUILD_REMOTE_DIR GIT_BRANCH
export BACKEND_REPO FRONTEND_REPO DEPLOY_REPO REMOTE_DIR SSH_HOST BUILD_SSH_HOST

# 1. build server: git pull + docker build
[ "$BUILD_BACKEND" = "1" ] && git_sync_remote ssh_build "$BUILD_SSH_HOST" "$BACKEND_REPO" "$BUILD_REMOTE_DIR/backend" "$GIT_BRANCH"
[ "$BUILD_FRONTEND" = "1" ] && git_sync_remote ssh_build "$BUILD_SSH_HOST" "$FRONTEND_REPO" "$BUILD_REMOTE_DIR/frontend" "$GIT_BRANCH"

ssh_build "$BUILD_SSH_HOST" \
  BUILD_BACKEND="$BUILD_BACKEND" BUILD_FRONTEND="$BUILD_FRONTEND" \
  PLATFORM="$PLATFORM" BACKEND_IMAGE="$BACKEND_IMAGE" FRONTEND_IMAGE="$FRONTEND_IMAGE" \
  BASE_URL="$BASE_URL" URL_PREFIX="$URL_PREFIX" GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID" \
  BUILD_REMOTE_DIR="$BUILD_REMOTE_DIR" bash -s <<'EOF'
set -euo pipefail
cd "$BUILD_REMOTE_DIR"
[ "$BUILD_BACKEND" != "1" ] || docker build --platform "$PLATFORM" -t "$BACKEND_IMAGE" backend
[ "$BUILD_FRONTEND" != "1" ] || docker build --platform "$PLATFORM" -t "$FRONTEND_IMAGE" \
  --build-arg BASE_URL="$BASE_URL" --build-arg URL_PREFIX="$URL_PREFIX" \
  --build-arg GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID" --build-arg NODE_ENV=production frontend
EOF

# 2. VPS: git pull deploy repo
git_sync_remote ssh_vps "$SSH_HOST" "$DEPLOY_REPO" "$REMOTE_DIR" "$GIT_BRANCH"

# 3. stream images + compose up
[ "$SYNC_BACKEND" = "1" ] && stream_image "$BACKEND_IMAGE"
[ "$SYNC_FRONTEND" = "1" ] && stream_image "$FRONTEND_IMAGE"

if [ "$SYNC_BACKEND" = "1" ] || [ "$SYNC_FRONTEND" = "1" ]; then
  UP="docker compose up -d"
  [ "$SYNC_BACKEND" = "1" ] && UP="$UP backend"
  [ "$SYNC_FRONTEND" = "1" ] && UP="$UP frontend"
  ssh_vps "$SSH_HOST" "cd $REMOTE_DIR && $UP"
fi

[ "$PRUNE_VPS_IMAGES" != "1" ] || ssh_vps "$SSH_HOST" "docker image prune -f"

echo PUBLISH_OK
