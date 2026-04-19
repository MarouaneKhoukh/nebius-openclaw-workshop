#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

load_env
require_cmd nebius
require_cmd jq

SUBNET_ID="$(resolve_subnet_id)"
BUCKET_ID="$(nebius storage bucket get-by-name --name "$BUCKET_NAME" --format jsonpath='{.metadata.id}')"

JOB_NAME="${TRAIN_JOB_NAME:?TRAIN_JOB_NAME is required}"

EXISTING_JOB_ID="$(nebius ai job get-by-name --name "$JOB_NAME" --format jsonpath='{.metadata.id}' 2>/dev/null || true)"
if [[ -n "$EXISTING_JOB_ID" ]]; then
  echo "job_id=$EXISTING_JOB_ID"
  nebius ai job get "$EXISTING_JOB_ID" --format json | json_get '.status.state'
  exit 0
fi

ARGS='-c "RUN_ID=run-$(date +%Y%m%d-%H%M%S); axolotl train /workspace/data/config.yaml && mkdir -p /workspace/data/output/$RUN_ID && cp -r /workspace/output/. /workspace/data/output/$RUN_ID"'

JOB_JSON="$(nebius ai job create \
  --name "$JOB_NAME" \
  --subnet-id "$SUBNET_ID" \
  --image "$TRAIN_IMAGE" \
  --platform "$TRAIN_PLATFORM" \
  --preset "$TRAIN_PRESET" \
  --disk-size "$TRAIN_DISK_SIZE" \
  --volume "$BUCKET_ID:$BUCKET_MOUNT_PATH" \
  --container-command bash \
  --args "$ARGS" \
  --format json)"

echo "$JOB_JSON" | json_get '"job_id=" + .metadata.id'
echo "$JOB_JSON" | json_get '"state=" + .status.state'
