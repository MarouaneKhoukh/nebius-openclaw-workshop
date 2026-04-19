#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${WORKSHOP_ENV_FILE:-$ROOT_DIR/.env}"

require_env_file() {
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "Missing env file: $ENV_FILE"
    echo "Copy .env.example to .env and fill required values."
    exit 1
  fi
}

load_env() {
  require_env_file
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
}

require_cmd() {
  local c="$1"
  if ! command -v "$c" >/dev/null 2>&1; then
    echo "Missing command: $c"
    exit 1
  fi
}

json_get() {
  jq -r "$1"
}
