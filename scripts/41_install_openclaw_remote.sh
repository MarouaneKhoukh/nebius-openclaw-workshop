#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

load_env
require_cmd ssh

VM_IP="${1:?Usage: $0 <vm_public_ip>}"

ssh -o StrictHostKeyChecking=accept-new "${CPU_VM_USER}@${VM_IP}" 'curl -fsSL https://openclaw.ai/install.sh | bash'
ssh "${CPU_VM_USER}@${VM_IP}" "echo 'export PATH=\"\$HOME/.npm-global/bin:\$PATH\"' >> ~/.bashrc"
