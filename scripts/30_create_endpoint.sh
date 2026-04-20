#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

load_env
require_cmd nebius
require_cmd jq
require_cmd openssl

PROJECT_ID="$(resolve_project_id)"
PARENT_ID="$PROJECT_ID" # Nebius --parent-id for buckets is the project id.

SUBNET_ID="$(resolve_subnet_id)"
BUCKET_ID="$(nebius storage bucket get-by-name --name "$BUCKET_NAME" --parent-id "$PARENT_ID" --format jsonpath='{.metadata.id}')"

if [[ -z "${ENDPOINT_RUN_ID:-}" ]]; then
  echo "ENDPOINT_RUN_ID is required (example: run-20260417-114332)"
  exit 1
fi

EXISTING_ID="$(nebius ai endpoint get-by-name --name "$ENDPOINT_NAME" --format jsonpath='{.metadata.id}' 2>/dev/null || true)"
if [[ -n "$EXISTING_ID" ]]; then
  JSON="$(nebius ai endpoint get "$EXISTING_ID" --format json)"
  echo "$JSON" | json_get '"endpoint_id=" + .metadata.id'
  echo "$JSON" | json_get '"state=" + .status.state'
  echo "$JSON" | json_get '"public_endpoint=" + (.status.public_endpoints[0] // "")'
  echo "$JSON" | json_get '"auth_token=" + (.spec.auth_token // "")'
  exit 0
fi

AUTH_TOKEN="$(openssl rand -hex 32)"
LORA_PATH="$BUCKET_MOUNT_PATH/$TRAIN_OUTPUT_PREFIX/$ENDPOINT_RUN_ID/$ENDPOINT_CHECKPOINT"

JSON="$(nebius ai endpoint create \
  --name "$ENDPOINT_NAME" \
  --image "$ENDPOINT_IMAGE" \
  --container-command "python3 -m vllm.entrypoints.openai.api_server" \
  --args "--model $ENDPOINT_MODEL --enable-lora --lora-modules $ENDPOINT_LORA_NAME=$LORA_PATH --enable-auto-tool-choice --tool-call-parser hermes --host 0.0.0.0 --port $ENDPOINT_PORT" \
  --platform "$ENDPOINT_PLATFORM" \
  --preset "$ENDPOINT_PRESET" \
  --public \
  --container-port "$ENDPOINT_PORT" \
  --auth token \
  --token "$AUTH_TOKEN" \
  --shm-size 16Gi \
  --volume "$BUCKET_ID:$BUCKET_MOUNT_PATH:ro" \
  --subnet-id "$SUBNET_ID" \
  --format json)"

echo "$JSON" | json_get '"endpoint_id=" + .metadata.id'
echo "$JSON" | json_get '"state=" + .status.state'
echo "$JSON" | json_get '"public_endpoint=" + (.status.public_endpoints[0] // "")'
echo "auth_token=$AUTH_TOKEN"
