#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

load_env
require_cmd nebius
require_cmd jq

PROJECT_ID="$(resolve_project_id)"

SUBNET_ID="$(resolve_subnet_id)"
BUCKET_ID="$(nebius storage bucket get-by-name --name "$BUCKET_NAME" --parent-id "$PROJECT_ID" --format jsonpath='{.metadata.id}')"

JOB_NAME="${TRAIN_JOB_NAME:?TRAIN_JOB_NAME is required}"

echo "=== variables used by this script ==="
echo "WORKSHOP_ENV_FILE=${WORKSHOP_ENV_FILE:-}"
echo "NEBIUS_SUBNET_ID=${NEBIUS_SUBNET_ID:-}"
echo "BUCKET_NAME=${BUCKET_NAME:?}"
echo "TRAIN_JOB_NAME=${TRAIN_JOB_NAME:?}"
echo "TRAIN_IMAGE=${TRAIN_IMAGE:?}"
echo "TRAIN_PLATFORM=${TRAIN_PLATFORM:?}"
echo "TRAIN_PRESET=${TRAIN_PRESET:?}"
echo "TRAIN_DISK_SIZE=${TRAIN_DISK_SIZE:?}"
echo "BUCKET_MOUNT_PATH=${BUCKET_MOUNT_PATH:?}"
echo "NEBIUS_PROJECT_ID=$PROJECT_ID"
echo "SUBNET_ID=$SUBNET_ID"
echo "BUCKET_ID=$BUCKET_ID"
echo "JOB_NAME=$JOB_NAME"
echo "=== end variables ==="

# get-by-name requires --parent-id (= project id); without it the CLI may use another scope and miss the job you see in the UI.
EXISTING_JOB_ID=""
if EXISTING_JSON="$(nebius ai job get-by-name --name "$JOB_NAME" --parent-id "$PROJECT_ID" --format json 2>/dev/null)"; then
  EXISTING_JOB_ID="$(printf '%s' "$EXISTING_JSON" | jq -r '.metadata.id // empty')"
fi
if [[ -n "$EXISTING_JOB_ID" ]]; then
  echo "existing_job_found=true job_id=$EXISTING_JOB_ID (name=$JOB_NAME parent_id=$PROJECT_ID)"
  nebius ai job get "$EXISTING_JOB_ID" --format json | json_get '.status.state'
  exit 0
fi

echo "existing_job_found=false creating name=$JOB_NAME parent_id=$PROJECT_ID"

ARGS='-c "RUN_ID=run-$(date +%Y%m%d-%H%M%S); axolotl train /workspace/data/config.yaml && mkdir -p /workspace/data/output/$RUN_ID && cp -r /workspace/output/. /workspace/data/output/$RUN_ID"'

echo "ARGS=$ARGS"

JOB_JSON="$(nebius ai job create \
  --parent-id "$PROJECT_ID" \
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
