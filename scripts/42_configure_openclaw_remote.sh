#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

load_env
require_cmd ssh

VM_IP="${1:?Usage: $0 <vm_public_ip> <endpoint_hostport> <endpoint_token>}"
ENDPOINT_HOSTPORT="${2:?missing endpoint_hostport}"
ENDPOINT_TOKEN="${3:?missing endpoint_token}"

ssh "${CPU_VM_USER}@${VM_IP}" "export PATH=\"\$HOME/.npm-global/bin:\$PATH\"; \
CONFIG_FILE=\"\$HOME/.openclaw/config.json\"; \
mkdir -p \"\$(dirname \$CONFIG_FILE)\"; \
if [[ -f \"\$CONFIG_FILE\" ]]; then \
  tmp=\$(mktemp); jq '.gateway.mode = \"local\"' \"\$CONFIG_FILE\" > \"\$tmp\" && mv \"\$tmp\" \"\$CONFIG_FILE\"; \
else \
  echo '{\"gateway\":{\"mode\":\"local\"}}' > \"\$CONFIG_FILE\"; \
fi; \
openclaw config set models.providers.nebius --strict-json '{\"baseUrl\":\"http://${ENDPOINT_HOSTPORT}/v1\",\"api\":\"openai-completions\",\"apiKey\":\"${ENDPOINT_TOKEN}\",\"models\":[{\"id\":\"qwen-support\",\"name\":\"qwen-support\",\"api\":\"openai-completions\",\"maxTokens\":256,\"contextWindow\":32768}]}' && \
openclaw models set ${OPENCLAW_MODEL} && \
openclaw daemon restart && \
openclaw models status --json"
