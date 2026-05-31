#!/bin/bash
set -euo pipefail

DEPLOY_REPO=https://github.com/inhouseaccman/mycloset-deploy.git
DEPLOY_DIR=/opt/deploy
GIT_BRANCH="${GIT_BRANCH:-master}"

sudo apt-get update
sudo apt-get install -y git docker.io docker-compose-v2 curl python3
sudo systemctl enable --now docker
sudo usermod -aG docker deploy

sudo mkdir -p "$DEPLOY_DIR"
if [ ! -d "$DEPLOY_DIR/.git" ]; then
  sudo git clone --branch "$GIT_BRANCH" "$DEPLOY_REPO" "$DEPLOY_DIR"
else
  sudo -u deploy bash "$DEPLOY_DIR/scripts/git-sync.sh" "$DEPLOY_REPO" "$DEPLOY_DIR" "$GIT_BRANCH"
fi

sudo mkdir -p "$DEPLOY_DIR/configs" "$DEPLOY_DIR/nginx/certs"
sudo bash "$DEPLOY_DIR/scripts/init-env.sh"
sudo chown -R deploy:deploy "$DEPLOY_DIR"
sudo chmod 600 "$DEPLOY_DIR/.env" "$DEPLOY_DIR/configs/secrets.ini"

echo BOOTSTRAP_OK
