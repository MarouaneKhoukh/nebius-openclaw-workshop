#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

load_env
require_cmd nebius
require_cmd jq

SUBNET_ID="$(resolve_subnet_id)"

if [[ ! -f "$HOME/.ssh/id_ed25519.pub" ]]; then
  echo "Missing ~/.ssh/id_ed25519.pub"
  echo "Create one: ssh-keygen -t ed25519"
  exit 1
fi

DISK_ID="$(nebius compute disk get-by-name --name "$CPU_DISK_NAME" --format jsonpath='{.metadata.id}' 2>/dev/null || true)"
if [[ -z "$DISK_ID" ]]; then
  DISK_ID="$(nebius compute disk create \
    --name "$CPU_DISK_NAME" \
    --size-gibibytes "$CPU_DISK_GB" \
    --type network_ssd \
    --source-image-family-image-family "$CPU_IMAGE_FAMILY" \
    --block-size-bytes 4096 \
    --format json | json_get '.metadata.id')"
fi

INSTANCE_ID="$(nebius compute instance get-by-name --name "$CPU_VM_NAME" --format jsonpath='{.metadata.id}' 2>/dev/null || true)"
if [[ -z "$INSTANCE_ID" ]]; then
  USER_DATA="$(cat <<EOF
users:
  - name: $CPU_VM_USER
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - $(cat "$HOME/.ssh/id_ed25519.pub")
EOF
)"
  USER_DATA_JSON="$(printf '%s' "$USER_DATA" | jq -Rs .)"

  SPEC="$(cat <<EOF
{
  "metadata": { "name": "$CPU_VM_NAME" },
  "spec": {
    "stopped": false,
    "cloud_init_user_data": $USER_DATA_JSON,
    "resources": { "platform": "$CPU_PLATFORM", "preset": "$CPU_PRESET" },
    "boot_disk": { "attach_mode": "READ_WRITE", "existing_disk": { "id": "$DISK_ID" } },
    "network_interfaces": [
      { "name": "openclaw-if0", "subnet_id": "$SUBNET_ID", "ip_address": {}, "public_ip_address": {} }
    ]
  }
}
EOF
)"
  INSTANCE_ID="$(printf '%s' "$SPEC" | nebius compute instance create --format json - | json_get '.metadata.id')"
fi

PUBLIC_IP="$(nebius compute instance get --id "$INSTANCE_ID" --format json | json_get '.status.network_interfaces[0].public_ip_address.address | split("/")[0]')"
echo "instance_id=$INSTANCE_ID"
echo "public_ip=$PUBLIC_IP"
