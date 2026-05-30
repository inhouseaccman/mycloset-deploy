#!/bin/bash
# 本機 cross-build（production 設定）並上傳至 VPS。
# 用法：
#   DEPLOY_ENV=production ./publish-images-local.sh
#   DEPLOY_ENV=production BUILD_BACKEND=0 SYNC_BACKEND=0 ./publish-images-local.sh   # 只更新 frontend
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

export DEPLOY_ENV="${DEPLOY_ENV:-production}"
export BUILD_BACKEND="${BUILD_BACKEND:-0}"
export BUILD_FRONTEND="${BUILD_FRONTEND:-1}"
export SYNC_BACKEND="${SYNC_BACKEND:-0}"
export SYNC_FRONTEND="${SYNC_FRONTEND:-1}"

bash "$SCRIPT_DIR/build-images-local.sh"
bash "$SCRIPT_DIR/sync-images-to-server.sh"

echo "PUBLISH_LOCAL_OK"
