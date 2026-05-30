#!/bin/bash
set -euo pipefail

DEPLOY_DIR=/opt/deploy
SRC_DIR=$DEPLOY_DIR/src
BACKEND_REPO=https://github.com/inhouseaccman/mycloset-backend.git
FRONTEND_REPO=https://github.com/inhouseaccman/mycloset-frontend.git
COMPOSE="docker compose"

setup_git_auth() {
  if git config --global --get-regexp '^url\..*\.insteadof$' https://github.com/ >/dev/null 2>&1; then
    return 0
  fi
  if [ -f "$HOME/.git-credentials" ]; then
    python3 - <<'PY'
from pathlib import Path
import subprocess

cred = Path.home().joinpath(".git-credentials").read_text().splitlines()[0].strip()
base = cred.rstrip("/") + "/"
subprocess.run(
    ["git", "config", "--global", f"url.{base}.insteadOf", "https://github.com/"],
    check=True,
)
PY
  fi
}

cd "$DEPLOY_DIR"
setup_git_auth
bash "$DEPLOY_DIR/scripts/init-env.sh"

echo "=== clone app repos ==="
mkdir -p "$SRC_DIR"
if [ -d "$SRC_DIR/backend/.git" ]; then
  git -C "$SRC_DIR/backend" pull origin master
else
  git clone "$BACKEND_REPO" "$SRC_DIR/backend"
fi
if [ -d "$SRC_DIR/frontend/.git" ]; then
  git -C "$SRC_DIR/frontend" pull origin master
else
  git clone "$FRONTEND_REPO" "$SRC_DIR/frontend"
fi

echo "=== 啟動 MySQL ==="
$COMPOSE up -d db

for i in $(seq 1 40); do
  cid=$($COMPOSE ps -q db)
  status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$cid" 2>/dev/null || echo starting)
  echo "db: $status"
  [ "$status" = "healthy" ] && break
  sleep 3
done

echo "=== 建置 backend ==="
export DEPLOY_ENV=production
export BUILD_FRONTEND=0
# shellcheck disable=SC1091
source "$DEPLOY_DIR/scripts/load-deploy-env.sh"
docker build -t "$BACKEND_IMAGE" --platform "$PLATFORM" "$SRC_DIR/backend"

echo "=== 建置 frontend ==="
export BUILD_FRONTEND=1
# shellcheck disable=SC1091
source "$DEPLOY_DIR/scripts/load-deploy-env.sh"
docker build -t "$FRONTEND_IMAGE" \
  --platform "$PLATFORM" \
  --build-arg BASE_URL="$BASE_URL" \
  --build-arg URL_PREFIX="$URL_PREFIX" \
  --build-arg GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID" \
  --build-arg NODE_ENV=production \
  "$SRC_DIR/frontend"

echo "=== 啟動全部服務 ==="
$COMPOSE up -d

for i in $(seq 1 40); do
  cid=$($COMPOSE ps -q backend)
  status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$cid" 2>/dev/null || echo starting)
  echo "backend: $status"
  [ "$status" = "healthy" ] && break
  sleep 3
done

echo "=== 資料庫 migration ==="
bash "$DEPLOY_DIR/scripts/migrate.sh"

echo "=== 服務狀態 ==="
$COMPOSE ps
curl -sf http://127.0.0.1/api/public/status/liveness && echo " API_OK" || echo " API_PENDING"
curl -sf -o /dev/null -w "frontend_http=%{http_code}\n" http://127.0.0.1/

echo "DEPLOY_OK"
