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

resolve_project_id() {
  local from_env="${NEBIUS_PROJECT_ID:-}"
  if [[ -n "$from_env" && "$from_env" != "project-xxxxxxxxxxxxxxxx" ]]; then
    echo "$from_env"
    return 0
  fi

  local from_cli
  from_cli="$(nebius config get parent-id 2>/dev/null || true)"
  if [[ -n "$from_cli" ]]; then
    echo "$from_cli"
    return 0
  fi

  echo "Unable to resolve project id."
  echo "Set NEBIUS_PROJECT_ID in .env or run:"
  echo "  nebius profile create"
  echo "  nebius config set parent-id <project_id>   # parent-id here is your project id"
  return 1
}

resolve_subnet_id() {
  local from_env="${NEBIUS_SUBNET_ID:-}"
  if [[ -n "$from_env" && "$from_env" != "subnet-xxxxxxxxxxxxxxxx" ]]; then
    echo "$from_env"
    return 0
  fi

  local from_cli
  from_cli="$(nebius vpc subnet list --format json 2>/dev/null | jq -r '.items[0].metadata.id // ""' || true)"
  if [[ -n "$from_cli" ]]; then
    echo "$from_cli"
    return 0
  fi

  echo "Unable to resolve subnet id."
  echo "Set NEBIUS_SUBNET_ID in .env or create/list subnets in Nebius."
  return 1
}
