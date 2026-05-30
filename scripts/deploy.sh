#!/bin/bash
set -euo pipefail

DEPLOY_DIR=/opt/deploy
SRC_DIR=$DEPLOY_DIR/src
BACKEND_REPO=https://github.com/inhouseaccman/mycloset-backend.git
FRONTEND_REPO=https://github.com/inhouseaccman/mycloset-frontend.git
DAOCLOUD=docker.m.daocloud.io/library

cd "$DEPLOY_DIR"

# 確保 MySQL image 使用可拉取的鏡像
python3 - <<'PY'
from pathlib import Path
p = Path("/opt/deploy/.env")
lines = []
for line in p.read_text().splitlines():
    if line.startswith("MYSQL_IMAGE="):
        lines.append("MYSQL_IMAGE=docker.m.daocloud.io/library/mysql:8.0")
    elif line.startswith("FRONTEND_IMAGE="):
        lines.append("FRONTEND_IMAGE=localhost/mycloset-frontend:latest")
    elif line.startswith("BACKEND_IMAGE="):
        lines.append("BACKEND_IMAGE=localhost/mycloset-backend:latest")
    elif line.startswith("NGINX_IMAGE="):
        continue
    else:
        lines.append(line)
if not any(x.startswith("NGINX_IMAGE=") for x in lines):
    lines.append("NGINX_IMAGE=docker.m.daocloud.io/library/nginx:1.27-alpine")
p.write_text("\n".join(lines) + "\n")
PY

echo "=== 啟動 MySQL ==="
podman pull ${DAOCLOUD}/mysql:8.0 || true
podman-compose up -d db

for i in $(seq 1 40); do
  status=$(podman inspect deploy_db_1 --format '{{.State.Health.Status}}' 2>/dev/null || echo starting)
  echo "db health: $status"
  [ "$status" = "healthy" ] && break
  sleep 3
done

mkdir -p "$SRC_DIR"
[ -d "$SRC_DIR/backend/.git" ] || git clone "$BACKEND_REPO" "$SRC_DIR/backend"
[ -d "$SRC_DIR/frontend/.git" ] || git clone "$FRONTEND_REPO" "$SRC_DIR/frontend"
git -C "$SRC_DIR/backend" pull origin master
git -C "$SRC_DIR/frontend" pull origin master

echo "=== 拉取 base images ==="
podman pull ${DAOCLOUD}/python:3.9.18-slim
podman pull ${DAOCLOUD}/node:18.12
podman pull ${DAOCLOUD}/nginx:1.27-alpine
podman tag ${DAOCLOUD}/python:3.9.18-slim python:3.9.18-slim || true
podman tag ${DAOCLOUD}/node:18.12 node:18.12 || true

echo "=== 建置 backend ==="
podman build -t localhost/mycloset-backend:latest "$SRC_DIR/backend"

echo "=== 建置 frontend ==="
podman build -t localhost/mycloset-frontend:latest \
  --build-arg BASE_URL=https://api.akikaycloset.vip \
  --build-arg URL_PREFIX= \
  --build-arg GOOGLE_CLIENT_ID=1099160565455-r2jlmn2i9ontham6nj3bh7jneunb4d7r.apps.googleusercontent.com \
  --build-arg NODE_ENV=production \
  "$SRC_DIR/frontend"

echo "=== 啟動全部服務 ==="
podman-compose up -d

for i in $(seq 1 40); do
  status=$(podman inspect deploy_backend_1 --format '{{.State.Health.Status}}' 2>/dev/null || echo starting)
  echo "backend health: $status"
  [ "$status" = "healthy" ] && break
  sleep 3
done

echo "=== 資料庫 migration ==="
podman exec deploy_backend_1 alembic upgrade head

echo "=== 服務狀態 ==="
podman ps --filter label=io.podman.compose.project=deploy
curl -sf http://127.0.0.1/api/public/status/liveness && echo " API_OK" || echo " API_PENDING"
curl -sf -o /dev/null -w "%{http_code}" http://127.0.0.1/ && echo " FRONTEND_OK"

echo "DEPLOY_OK"
