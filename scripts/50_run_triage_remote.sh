#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

load_env
require_cmd ssh
require_cmd scp

VM_IP="${1:?Usage: $0 <vm_public_ip>}"
REMOTE_DIR="${2:-~/nebius-openclaw-workshop}"

ssh "${CPU_VM_USER}@${VM_IP}" "mkdir -p $REMOTE_DIR"

scp "$ROOT_DIR/../support_tickets.csv" "${CPU_VM_USER}@${VM_IP}:$REMOTE_DIR/support_tickets.csv"
scp "$ROOT_DIR/scripts/triage_runner.py" "${CPU_VM_USER}@${VM_IP}:$REMOTE_DIR/triage_runner.py"

ssh -T "${CPU_VM_USER}@${VM_IP}" "\
export WORKSHOP_DIR=$REMOTE_DIR; \
export OPENCLAW_BIN='${OPENCLAW_BIN}'; \
export OPENCLAW_MODEL='${OPENCLAW_MODEL}'; \
export OPENCLAW_SESSION_FILE='${OPENCLAW_SESSION_FILE}'; \
export TRIAGE_TIMEOUT_SEC='${TRIAGE_TIMEOUT_SEC}'; \
export TELEGRAM_BOT_TOKEN='${TELEGRAM_BOT_TOKEN}'; \
export TELEGRAM_CHAT_ID='${TELEGRAM_CHAT_ID}'; \
python3 $REMOTE_DIR/triage_runner.py"
