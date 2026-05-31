#!/bin/bash
# VPS 本機：git sync deploy repo → 啟動服務 → migration
set -euo pipefail

DEPLOY_DIR=/opt/deploy
GIT_BRANCH="${GIT_BRANCH:-master}"
DEPLOY_REPO="${DEPLOY_REPO:-https://github.com/inhouseaccman/mycloset-deploy.git}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1090
source "$SCRIPT_DIR/lib.sh"

cd "$DEPLOY_DIR"
bash "$SCRIPT_DIR/git-sync.sh" "$DEPLOY_REPO" "$DEPLOY_DIR" "$GIT_BRANCH"
bash "$SCRIPT_DIR/init-env.sh"

docker compose up -d db
wait_healthy db
docker compose up -d
wait_healthy backend
bash "$SCRIPT_DIR/migrate.sh"
docker compose ps

echo DEPLOY_OK
