#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

load_env
require_cmd ssh

VM_IP="${1:?Usage: $0 <vm_public_ip>}"
SSH_TARGET="${CPU_VM_USER}@${VM_IP}"

echo "[1/4] Install OpenClaw on ${SSH_TARGET}"
ssh -o StrictHostKeyChecking=accept-new "${SSH_TARGET}" "bash -lc '
  set -euo pipefail
  curl -fsSL https://openclaw.ai/install.sh | OPENCLAW_VERSION=2026.1.29 bash || true
  command -v openclaw >/dev/null || test -x \"\$HOME/.npm-global/bin/openclaw\"
'"

echo "[2/4] Persist PATH for new sessions"
ssh "${SSH_TARGET}" "bash -lc '
  grep -q \"npm-global/bin\" ~/.bashrc || echo \"export PATH=\\\"\\\$HOME/.npm-global/bin:\\\$PATH\\\"\" >> ~/.bashrc
'"

echo "[3/4] Configure OpenClaw and restart daemon"
if ! ssh "${SSH_TARGET}" "bash -lc '
  export PATH=\"\$HOME/.npm-global/bin:\$PATH\"
  openclaw config set gateway.mode local
  openclaw daemon install
  for attempt in 1 2 3 4 5; do
    openclaw daemon restart || true
    sleep 3
    openclaw daemon status || true
    if ss -ltn \"( sport = :18789 )\" | awk \"NR>1{found=1} END{exit found?0:1}\"; then
      echo \"Gateway port 18789 is listening\"
      exit 0
    fi
    echo \"Gateway port 18789 is not ready (attempt \$attempt/5)\"
  done
  exit 1
'"; then
  echo "[4/4] Daemon health check failed, collecting remote diagnostics"
  ssh "${SSH_TARGET}" "bash -lc '
    export PATH=\"\$HOME/.npm-global/bin:\$PATH\"
    echo \"--- openclaw status ---\"
    openclaw status || true
    echo \"--- daemon status ---\"
    openclaw daemon status || true
    echo \"--- systemd logs ---\"
    journalctl --user -u openclaw-gateway.service -n 200 --no-pager || true
    echo \"--- file logs ---\"
    ls -1t /tmp/openclaw/openclaw-*.log 2>/dev/null | head -n 1 | xargs -I{} sh -c \"echo {} && tail -n 200 {}\"
  '"
  exit 1
fi
