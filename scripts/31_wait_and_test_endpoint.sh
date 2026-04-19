#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

load_env
require_cmd nebius
require_cmd jq
require_cmd curl

ENDPOINT_ID="${1:-$(nebius ai endpoint get-by-name --name "$ENDPOINT_NAME" --format jsonpath='{.metadata.id}')}"
AUTH_TOKEN="${2:-}"
if [[ -z "$AUTH_TOKEN" ]]; then
  AUTH_TOKEN="$(nebius ai endpoint get "$ENDPOINT_ID" --format json | json_get '.spec.auth_token')"
fi

PUBLIC_ENDPOINT=""
for _ in {1..60}; do
  JSON="$(nebius ai endpoint get "$ENDPOINT_ID" --format json)"
  STATE="$(echo "$JSON" | json_get '.status.state')"
  PUBLIC_ENDPOINT="$(echo "$JSON" | json_get '.status.public_endpoints[0] // ""')"
  echo "state=$STATE endpoint=$PUBLIC_ENDPOINT"
  if [[ "$STATE" == "RUNNING" && -n "$PUBLIC_ENDPOINT" ]]; then
    break
  fi
  sleep 10
done

if [[ -z "$PUBLIC_ENDPOINT" ]]; then
  echo "endpoint_not_ready=true"
  exit 1
fi

curl -sS "http://$PUBLIC_ENDPOINT/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AUTH_TOKEN" \
  -d "{\"model\":\"$ENDPOINT_LORA_NAME\",\"messages\":[{\"role\":\"user\",\"content\":\"Does the API support Python 3.12?\"}]}" \
  | jq -r '.choices[0].message.content // .'
