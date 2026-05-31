#!/bin/bash
set -euo pipefail

_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$_DIR/../.." && pwd)"
SSH_CONFIG_BUILD="${SSH_CONFIG_BUILD:-$ROOT_DIR/.ssh/config}"

ssh_vps() {
  if [ -n "${SSH_CONFIG_VPS:-}" ]; then
    ssh -F "$SSH_CONFIG_VPS" -o BatchMode=yes "$@"
  else
    ssh -o BatchMode=yes "$@"
  fi
}

ssh_build() {
  ssh -F "$SSH_CONFIG_BUILD" -o BatchMode=yes "$@"
}

git_sync_remote() {
  local runner="$1" host="$2"
  shift 2
  "$runner" "$host" bash -s -- "$@" < "$_DIR/git-sync.sh"
}

stream_image() {
  local image="$1"
  ssh_build "$BUILD_SSH_HOST" "docker save '$image' | gzip -c" | \
    ssh_vps "$SSH_HOST" "gunzip | docker load"
}

wait_healthy() {
  local svc="$1"
  for _ in $(seq 1 40); do
    local cid status
    cid=$(docker compose ps -q "$svc")
    status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$cid" 2>/dev/null || echo starting)
    echo "$svc: $status"
    [ "$status" = "healthy" ] && return 0
    sleep 3
  done
  return 1
}
