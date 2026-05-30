#!/bin/bash
set -euo pipefail

DEPLOY_REPO=https://github.com/inhouseaccman/mycloset-deploy.git
DEPLOY_DIR=/opt/deploy

echo "=== 安裝依賴 ==="
sudo apt-get update
sudo apt-get install -y git docker.io docker-compose-v2 curl

sudo systemctl enable --now docker
sudo usermod -aG docker deploy

echo "=== clone deploy repo ==="
sudo mkdir -p "$DEPLOY_DIR"
if [ -d "$DEPLOY_DIR/.git" ]; then
  sudo git -C "$DEPLOY_DIR" pull origin master
else
  sudo git clone "$DEPLOY_REPO" "$DEPLOY_DIR"
fi

sudo mkdir -p "$DEPLOY_DIR/configs" "$DEPLOY_DIR/nginx/certs" "$DEPLOY_DIR/nginx/pki-validation"
sudo bash "$DEPLOY_DIR/scripts/init-env.sh"
sudo chown -R deploy:deploy "$DEPLOY_DIR"
sudo chmod 600 "$DEPLOY_DIR/.env" "$DEPLOY_DIR/configs/secrets.ini"

echo "BOOTSTRAP_OK"
