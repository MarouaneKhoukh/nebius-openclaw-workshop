#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

load_env
require_cmd nebius
require_cmd aws
require_cmd jq
require_cmd curl

echo "nebius: $(nebius version)"
echo "aws: $(aws --version 2>&1)"
echo "jq: $(jq --version)"

if ! nebius config get parent-id >/dev/null 2>&1; then
  echo "Nebius parent-id is not configured."
  echo "Run: nebius profile create"
  echo "Then: nebius config set parent-id <your_project_id>"
  exit 1
fi

PROJECT_ID="$(nebius config get parent-id)"
echo "project_id: $PROJECT_ID"

SUBNET="${NEBIUS_SUBNET_ID:-}"
if [[ -z "$SUBNET" ]]; then
  SUBNET="$(nebius vpc subnet list --format json | json_get '.items[0].metadata.id')"
  echo "derived_subnet_id: $SUBNET"
  echo "Tip: set NEBIUS_SUBNET_ID=$SUBNET in .env"
else
  echo "subnet_id: $SUBNET"
fi

echo "Prereq check passed."
