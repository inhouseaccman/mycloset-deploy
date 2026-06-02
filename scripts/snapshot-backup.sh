#!/bin/bash
set -euo pipefail

ENV_FILE="${SNAPSHOT_ENV_FILE:-/opt/deploy/configs/snapshot.env}"
CREDS_FILE="${SNAPSHOT_CREDS_FILE:-/opt/deploy/configs/snapshot.credentials.env}"

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

if [ -f "$CREDS_FILE" ]; then
  # shellcheck disable=SC1090
  source "$CREDS_FILE"
fi

REGION_ID="${REGION_ID:-cn-hongkong}"
PROFILE="${ALIYUN_PROFILE:-sas-snapshot}"
KEEP="${KEEP_SNAPSHOTS:-2}"
INSTANCE_ID="${INSTANCE_ID:-}"
DISK_ID="${DISK_ID:-}"
PUBLIC_IP="${PUBLIC_IP:-}"
SNAPSHOT_PREFIX="${SNAPSHOT_PREFIX:-weekly-auto}"
LOG_TAG="sas-snapshot"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$LOG_TAG] $*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"
}

ensure_swas_plugin() {
  if ! aliyun swas-open list-regions --help >/dev/null 2>&1; then
    fail "missing swas-open CLI plugin; run: aliyun plugin install --names aliyun-cli-swas-open"
  fi
}

configure_profile_from_env() {
  if [ -z "${ALIBABA_CLOUD_ACCESS_KEY_ID:-}" ] || [ -z "${ALIBABA_CLOUD_ACCESS_KEY_SECRET:-}" ]; then
    return 0
  fi
  aliyun configure set \
    --profile "$PROFILE" \
    --mode AK \
    --access-key-id "$ALIBABA_CLOUD_ACCESS_KEY_ID" \
    --access-key-secret "$ALIBABA_CLOUD_ACCESS_KEY_SECRET" \
    --region "$REGION_ID" >/dev/null
}

resolve_public_ip() {
  if [ -n "$PUBLIC_IP" ]; then
    return 0
  fi
  PUBLIC_IP=$(curl -s --connect-timeout 2 http://100.100.100.200/latest/meta-data/eipv4 2>/dev/null || true)
}

discover_instance_and_disk() {
  if [ -n "$INSTANCE_ID" ] && [ -n "$DISK_ID" ]; then
    log "using InstanceId=$INSTANCE_ID DiskId=$DISK_ID"
    return 0
  fi

  local instances_json
  if [ -n "$INSTANCE_ID" ]; then
    instances_json=$("${ALIYUN[@]}" swas-open list-instances \
      --biz-region-id "$REGION_ID" \
      --instance-ids "$INSTANCE_ID" \
      --page-size 10)
  else
    resolve_public_ip
    if [ -n "$PUBLIC_IP" ]; then
      instances_json=$("${ALIYUN[@]}" swas-open list-instances \
        --biz-region-id "$REGION_ID" \
        --public-ip-addresses "[\"$PUBLIC_IP\"]" \
        --page-size 10 2>/dev/null || true)
    fi
    if [ -z "${instances_json:-}" ] || [ "$(echo "$instances_json" | jq -r '.Instances | length // 0')" = "0" ]; then
      instances_json=$("${ALIYUN[@]}" swas-open list-instances \
        --biz-region-id "$REGION_ID" \
        --page-size 10)
    fi
  fi

  INSTANCE_ID=${INSTANCE_ID:-$(echo "$instances_json" | jq -r '.Instances[0].InstanceId // empty')}
  [ -n "$INSTANCE_ID" ] || fail "cannot discover InstanceId; set INSTANCE_ID in $ENV_FILE"

  if [ -z "$DISK_ID" ]; then
    local disks_json
    disks_json=$("${ALIYUN[@]}" swas-open list-disks \
      --biz-region-id "$REGION_ID" \
      --instance-id "$INSTANCE_ID" \
      --disk-type system \
      --page-size 10)
    DISK_ID=$(echo "$disks_json" | jq -r '.Disks[0].DiskId // empty')
  fi

  [ -n "$DISK_ID" ] || fail "cannot discover DiskId; set DISK_ID in $ENV_FILE"
  log "using InstanceId=$INSTANCE_ID DiskId=$DISK_ID"
}

delete_old_snapshots() {
  local snapshots_json progressing
  snapshots_json=$("${ALIYUN[@]}" swas-open list-snapshots \
    --biz-region-id "$REGION_ID" \
    --instance-id "$INSTANCE_ID" \
    --disk-id "$DISK_ID" \
    --page-size 50)

  progressing=$(echo "$snapshots_json" | jq -r '.Snapshots[]? | select((.Status // "" | ascii_downcase) == "progressing") | .SnapshotId' | head -n1)
  if [ -n "$progressing" ]; then
    fail "snapshot $progressing is still Progressing; skip this run"
  fi

  mapfile -t SNAPSHOT_IDS < <(
    echo "$snapshots_json" | jq -r '.Snapshots[]? | select((.Status // "" | ascii_downcase) == "accomplished") | [.CreationTime, .SnapshotId] | @tsv' \
      | sort \
      | awk '{print $NF}'
  )

  local count=${#SNAPSHOT_IDS[@]}
  if (( count >= KEEP )); then
    local delete_count=$((count - KEEP + 1))
    local i
    for (( i=0; i<delete_count; i++ )); do
      log "deleting old snapshot ${SNAPSHOT_IDS[$i]}"
      "${ALIYUN[@]}" swas-open delete-snapshot \
        --biz-region-id "$REGION_ID" \
        --snapshot-id "${SNAPSHOT_IDS[$i]}"
    done
  fi
}

create_snapshot() {
  local name="${SNAPSHOT_PREFIX}-$(date +%Y%m%d-%H%M)"
  log "creating snapshot $name"
  "${ALIYUN[@]}" swas-open create-snapshot \
    --biz-region-id "$REGION_ID" \
    --disk-id "$DISK_ID" \
    --snapshot-name "$name"
  log "create request submitted for $name"
}

main() {
  require_cmd aliyun
  require_cmd jq
  ensure_swas_plugin

  configure_profile_from_env

  ALIYUN=(aliyun --profile "$PROFILE")
  if ! aliyun configure get --profile "$PROFILE" >/dev/null 2>&1; then
    fail "aliyun profile '$PROFILE' not configured; run: aliyun configure --profile $PROFILE"
  fi

  discover_instance_and_disk
  delete_old_snapshots
  create_snapshot
  log "done"
}

main "$@"
