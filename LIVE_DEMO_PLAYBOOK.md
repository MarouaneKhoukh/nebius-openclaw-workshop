# Live Demo Playbook - User Guide

This playbook is a workshop-friendly runbook for fine-tuning Qwen, serving it with vLLM + LoRA, and then using it from OpenClaw.

The main rule for this document is: keep shell variable names compatible with the scripts in `scripts/`. When a script already exists, use it first. Use raw `nebius ai ... create` commands mainly to understand what the script is doing or to debug a specific step.

Useful references while you run the workshop:

- [Serverless AI docs](https://docs.nebius.com/serverless)
- [Managing jobs in Serverless AI](https://docs.nebius.com/serverless/jobs/manage)
- [Fine-tuning with Axolotl](https://docs.nebius.com/serverless/tutorials/fine-tuning)
- [Deploying a vLLM endpoint](https://docs.nebius.com/serverless/tutorials/deploy-model)
- [Nebius CLI AI reference](https://docs.nebius.com/cli/reference/ai/index)
- [Serverless Cookbook](https://github.com/mnrozhkov/serverless-cookbook)

## Settings

### 1) Prerequisites and auth

Clone the repo and create your local env file:

```bash
git clone https://github.com/MarouaneKhoukh/nebius-openclaw-workshop.git
cd nebius-openclaw-workshop
cp .env.example .env
```

Run the preflight script first:

```bash
./scripts/00_check_prereqs.sh
```

That script checks the tools used by the workshop and resolves your Nebius project and subnet.

If something is missing:

- Nebius CLI install: [docs.nebius.com/cli](https://docs.nebius.com/cli)
- AWS CLI install: [docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)

Authenticate Nebius and set your project context if needed:

```bash
nebius auth login
nebius profile create
# Or, if the profile already exists:
# nebius config set parent-id <project_id>
```

### 2) Fill `.env`

Follow the setup notes in `README.md`, especially the Telegram setup and preflight checks.

The workshop scripts use the variable names from `.env.example`. Fill the required values there and keep the defaults for the rest unless you want to override them:

```env
# Nebius project + network
PROJECT_ID=project-xxxxxxxxxxxxxxxx
SUBNET_ID=

# Object storage
BUCKET_NAME=
BUCKET_ID=
BUCKET_MOUNT_PATH=/workspace/data

# Fine-tuning job
TRAIN_JOB_NAME=workshop-qwen-finetune-v2
TRAIN_IMAGE=docker.io/axolotlai/axolotl:main-20260309-py3.11-cu128-2.9.1
TRAIN_PLATFORM=gpu-l40s-a
TRAIN_PRESET=1gpu-8vcpu-32gb
TRAIN_DISK_SIZE=450Gi
TRAIN_CONFIG_OBJECT=config.yaml
TRAIN_DATA_OBJECT=faq_train.jsonl
TRAIN_OUTPUT_PREFIX=output

# Endpoint
ENDPOINT_NAME=workshop-qwen-endpoint-v2
ENDPOINT_IMAGE=vllm/vllm-openai:v0.18.0-cu130
ENDPOINT_PLATFORM=gpu-l40s-a
ENDPOINT_PRESET=1gpu-8vcpu-32gb
ENDPOINT_PORT=8000
ENDPOINT_MODEL=Qwen/Qwen2.5-0.5B
ENDPOINT_LORA_NAME=qwen-support
RUN_ID=
ENDPOINT_CHECKPOINT=checkpoint-50

# Telegram escalation
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
```

Notes for new users:

- Leave `SUBNET_ID` empty unless you want to pin a specific subnet. The scripts auto-pick the first subnet.
- Leave `BUCKET_NAME` empty if you want `scripts/10_bootstrap_storage.sh` to auto-generate a unique bucket name.
- Do not invent new variable names in this guide. Downstream scripts expect exactly the names from `.env.example`.

Load the env file into your shell before running manual commands:

```bash
set -a
source .env
set +a
```

If you want to confirm what the workshop will use:

```bash
PROJECT_ID="${PROJECT_ID:-$(nebius config get parent-id)}"
SUBNET_ID="${SUBNET_ID:-$(nebius vpc subnet list --format json | jq -r '.items[0].metadata.id')}"
echo "PROJECT_ID=${PROJECT_ID}"
echo "SUBNET_ID=${SUBNET_ID}"
echo "TRAIN_JOB_NAME=${TRAIN_JOB_NAME}"
echo "ENDPOINT_NAME=${ENDPOINT_NAME}"
```

### 3) Create object storage and upload training files

Recommended path:

```bash
./scripts/10_bootstrap_storage.sh
```

This script:

- creates or reuses the workshop bucket
- creates an access key for S3-compatible access
- configures AWS CLI
- uploads `config.yaml` and `faq_train.jsonl`

This is the easiest path for the workshop and keeps the run aligned with the rest of the scripts.

If you want a UI walkthrough instead, use the bucket preparation section from the official [Axolotl fine-tuning tutorial](https://docs.nebius.com/serverless/tutorials/fine-tuning).

Manual equivalent, only if you need to debug the storage step:

```bash
S3_ENDPOINT="https://storage.eu-north1.nebius.cloud"

aws s3 cp "${TRAIN_CONFIG_OBJECT}" "s3://${BUCKET_NAME}/${TRAIN_CONFIG_OBJECT}" \
  --endpoint-url "${S3_ENDPOINT}"
aws s3 cp "${TRAIN_DATA_OBJECT}" "s3://${BUCKET_NAME}/${TRAIN_DATA_OBJECT}" \
  --endpoint-url "${S3_ENDPOINT}"
aws s3 ls "s3://${BUCKET_NAME}/" --endpoint-url "${S3_ENDPOINT}"
```

Before continuing, make sure `.env` contains valid `BUCKET_NAME` and `BUCKET_ID`.

## 4) Submit fine-tuning job

Recommended path:

```bash
./scripts/20_submit_finetune_job.sh
```

The script already uses the workshop defaults from `.env.example`, checks for an existing job with the same name, and prints the created `job_id`.

Manual equivalent with the same env variables and defaults:

```bash
ARGS='-c "RUN_ID=run-$(date +%Y%m%d-%H%M%S); axolotl train /workspace/data/config.yaml && mkdir -p /workspace/data/output/${RUN_ID} && cp -r /workspace/output/. /workspace/data/output/${RUN_ID}"'

nebius ai job create \
  --parent-id "${PROJECT_ID}" \
  --name "workshop-qwen-finetune-v2" \
  --subnet-id "${SUBNET_ID}" \
  --image "docker.io/axolotlai/axolotl:main-20260309-py3.11-cu128-2.9.1" \
  --platform "gpu-l40s-a" \
  --preset "1gpu-8vcpu-32gb" \
  --disk-size "450Gi" \
  --volume "${BUCKET_ID}:${BUCKET_MOUNT_PATH}" \
  --container-command bash \
  --args "${ARGS}"
```

If you get stuck on job creation, logs, or cancellation, keep the [job management guide](https://docs.nebius.com/serverless/jobs/manage) open.

This is intentionally short: most values come from `.env`, so users can copy one command without hunting for platform, preset, disk size, or image values.

After the job is created, save the job ID in your shell:

```bash
JOB_ID=<job_id>
echo "JOB_ID=${JOB_ID}"
```

To watch progress, either use the script:

```bash
./scripts/21_watch_finetune_job.sh "${JOB_ID}"
```

Or follow logs directly:

```bash
nebius ai job logs "${JOB_ID}" --follow
```

The training job writes outputs under:

```text
output/run-YYYYMMDD-HHMMSS/
```

When training finishes, copy the generated `RUN_ID` (`run-YYYYMMDD-HHMMSS`) and set it in `.env` as:

```bash
RUN_ID=<run_id>
```

This keeps the next endpoint step compatible with `scripts/30_create_endpoint.sh`.

If the job fails, use the [job management and logs guide](https://docs.nebius.com/serverless/jobs/manage) and compare the command shape with the official [Axolotl fine-tuning example](https://docs.nebius.com/serverless/tutorials/fine-tuning).

---

## 5) Create serving endpoint (vLLM + LoRA)

```bash
ENDPOINT_AUTH_TOKEN="$(openssl rand -hex 32)"
LORA_PATH="${BUCKET_MOUNT_PATH}/${TRAIN_OUTPUT_PREFIX}/${RUN_ID}/${ENDPOINT_CHECKPOINT}"
echo "${LORA_PATH}"

nebius ai endpoint create \
  --parent-id "${PROJECT_ID}" \
  --name "${ENDPOINT_NAME}" \
  --image "vllm/vllm-openai:v0.18.0-cu130" \
  --container-command "python3 -m vllm.entrypoints.openai.api_server" \
  --args "--model ${ENDPOINT_MODEL} --enable-lora --lora-modules ${ENDPOINT_LORA_NAME}=${LORA_PATH} --enable-auto-tool-choice --tool-call-parser hermes --host 0.0.0.0 --port 8000" \
  --platform "gpu-l40s-a" \
  --preset "1gpu-8vcpu-32gb" \
  --public \
  --container-port "8000" \
  --auth token \
  --token "${ENDPOINT_AUTH_TOKEN}" \
  --shm-size 16Gi \
  --volume "${BUCKET_ID}:${BUCKET_MOUNT_PATH}:ro" \
  --subnet-id "${SUBNET_ID}"
```

Get endpoint details

```bash
export ENDPOINT_ID=<endpoint_id>
nebius ai endpoint get "${ENDPOINT_ID}"
```

Copy `Public:` and `auth_token` from the command output above and set them:

```bash
export ENDPOINT_PUBLIC_ENDPOINT=<public_ip:port>
export AUTH_TOKEN=<auth_token>
echo "${ENDPOINT_PUBLIC_ENDPOINT}"
```

Smoke test:

```bash
curl -sS "http://${ENDPOINT_PUBLIC_ENDPOINT}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${AUTH_TOKEN}" \
  -d "{\"model\":\"${ENDPOINT_LORA_NAME}\",\"messages\":[{\"role\":\"user\",\"content\":\"Say HI to all AI builders?\"}]}" \
  | jq -r '.choices[0].message.content // .'
```

---

## 7) Create and setup an OpenClaw instance 

Use README as the source of truth for this stage: follow `8) Create CPU VM for OpenClaw`.

Creata a CPU VM 
```bash
./scripts/40_create_cpu_vm.sh
```

Set env vars and run scripts:

```bash

export VM_PUBLIC_IP="<public_ip_from_output>"
./scripts/41_install_openclaw_remote.sh "${VM_PUBLIC_IP}"
```

---

Point OpenClaw to your Nebius endpoint, then process tickets and escalate failures to Telegram.

```bash
./scripts/42_configure_openclaw_remote.sh "${VM_PUBLIC_IP}" "${ENDPOINT_PUBLIC_ENDPOINT}" "${AUTH_TOKEN}"
./scripts/50_run_triage_remote.sh "${VM_PUBLIC_IP}"
```

---

## 11) Run OpenClaw as a serverless endpoint (with custom LLM endpoint)

This section replaces the CPU VM path and runs OpenClaw itself on Nebius Serverless CPU, while keeping your custom model on a separate endpoint.

### Prerequisites

You should already have:

- a running custom LLM endpoint (from step 5)
- endpoint host:port (public endpoint)
- endpoint auth token

Export them if needed:

```bash
export ENDPOINT_PUBLIC_ENDPOINT="<custom_llm_host:port>"
export AUTH_TOKEN="<custom_llm_endpoint_token>"
```

### 1) Build OpenClaw config

Generate a dedicated OpenClaw gateway token and config that points to your custom endpoint:

```bash
export OPENCLAW_GATEWAY_TOKEN="$(openssl rand -hex 32)"

OPENCLAW_CONFIG=$(cat <<EOF
{
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "controlUi": {
      "dangerouslyAllowHostHeaderOriginFallback": true,
      "dangerouslyDisableDeviceAuth": true
    },
    "auth": {
      "mode": "token",
      "token": "${OPENCLAW_GATEWAY_TOKEN}"
    },
    "http": {
      "endpoints": {
        "chatCompletions": { "enabled": true }
      }
    }
  },
  "models": {
    "providers": {
      "nebius": {
        "baseUrl": "http://${ENDPOINT_PUBLIC_ENDPOINT}/v1",
        "apiKey": "${AUTH_TOKEN}",
        "api": "openai-completions",
        "models": [
          {
            "id": "qwen-support",
            "name": "qwen-support",
            "api": "openai-completions",
            "maxTokens": 256,
            "contextWindow": 32768
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "nebius/qwen-support"
      }
    }
  }
}
EOF
)

OPENCLAW_CONFIG_B64=$(printf '%s' "${OPENCLAW_CONFIG}" | base64 | tr -d '\n')
```

### 2) Create OpenClaw serverless CPU endpoint

```bash
export OPENCLAW_ENDPOINT_NAME="workshop-openclaw-serverless"
export OPENCLAW_PORT="18789"
export SUBNET_ID="${SUBNET_ID:-$(nebius vpc subnet list --format json | jq -r '.items[0].metadata.id')}"

nebius ai endpoint create \
  --parent-id "${PROJECT_ID}" \
  --name "${OPENCLAW_ENDPOINT_NAME}" \
  --image ghcr.io/openclaw/openclaw:latest \
  --container-command bash \
  --args "-lc 'mkdir -p /home/node/.openclaw && echo ${OPENCLAW_CONFIG_B64} | base64 -d > /home/node/.openclaw/openclaw.json && cd /app && node dist/index.js gateway run --port ${OPENCLAW_PORT} --bind lan --allow-unconfigured'" \
  --platform cpu-d3 \
  --preset 8vcpu-32gb \
  --public \
  --container-port "${OPENCLAW_PORT}" \
  --subnet-id "${SUBNET_ID}" \
  --env "OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}"
```

### 3) Wait until RUNNING and get public endpoint

```bash
export OPENCLAW_ENDPOINT_ID="$(nebius ai endpoint get-by-name --name "${OPENCLAW_ENDPOINT_NAME}" --parent-id "${PROJECT_ID}" --format jsonpath='{.metadata.id}')"

for _ in {1..60}; do
  JSON="$(nebius ai endpoint get "${OPENCLAW_ENDPOINT_ID}" --format json)"
  STATE="$(echo "${JSON}" | jq -r '.status.state')"
  OPENCLAW_PUBLIC_ENDPOINT="$(echo "${JSON}" | jq -r '.status.public_endpoints[0] // empty')"
  echo "state=${STATE} endpoint=${OPENCLAW_PUBLIC_ENDPOINT}"
  [[ "${STATE}" == "RUNNING" && -n "${OPENCLAW_PUBLIC_ENDPOINT}" ]] && break
  sleep 10
done
```

### 4) Smoke test OpenClaw API

```bash
curl -sS "http://${OPENCLAW_PUBLIC_ENDPOINT}/v1/chat/completions" \
  -H "Authorization: Bearer ${OPENCLAW_GATEWAY_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openclaw",
    "messages": [{"role":"user","content":"Say hello from OpenClaw serverless"}]
  }' | jq -r '.choices[0].message.content // .'
```

### 5) Verify OpenClaw is using your custom LLM endpoint

Run endpoint logs in one terminal and send a traced OpenClaw request in another terminal.

Terminal A (watch custom LLM endpoint logs):

```bash
export LLM_ENDPOINT_ID="$(nebius ai endpoint get-by-name --name "${ENDPOINT_NAME}" --parent-id "${PROJECT_ID}" --format jsonpath='{.metadata.id}')"
nebius ai endpoint logs --follow "${LLM_ENDPOINT_ID}"
```

Terminal B (send request through OpenClaw):

```bash
TRACE_ID="OC_ROUTE_$(date +%s)"
curl -sS "http://${OPENCLAW_PUBLIC_ENDPOINT}/v1/chat/completions" \
  -H "Authorization: Bearer ${OPENCLAW_GATEWAY_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"openclaw\",
    \"messages\": [{\"role\":\"user\",\"content\":\"Reply exactly: ${TRACE_ID}\"}]
  }" | jq .
```

How to validate:

- If OpenClaw is routing correctly, Terminal A shows new request activity when Terminal B runs.
- Keep the trace text (`TRACE_ID`) unique so it is easy to correlate requests.

### 6) Open UI via HTTPS tunnel (required for browser WebCrypto)

```bash
cloudflared tunnel --url "http://${OPENCLAW_PUBLIC_ENDPOINT}"
```

Open the generated `https://...trycloudflare.com` URL, then use:

- WebSocket URL: auto-filled from the tunnel URL
- Gateway Token: `${OPENCLAW_GATEWAY_TOKEN}`

### Notes

- This setup keeps model serving and gateway separated (GPU endpoint for model, CPU endpoint for OpenClaw).
- For production, avoid unauthenticated public exposure; add platform-level auth/network restrictions.
- If latency is high on first request, that is expected from serverless cold starts.

### Cleanup

```bash
nebius ai endpoint delete "${OPENCLAW_ENDPOINT_ID}"
```

## Useful links

- [Serverless docs](https://docs.nebius.com/serverless)
- [Guide: manage jobs, endpoints, and logs](https://docs.nebius.com/serverless/jobs/manage)
- [Example: fine-tune with Axolotl](https://docs.nebius.com/serverless/tutorials/fine-tuning)
- [Example: vLLM with Qwen](https://docs.nebius.com/serverless/tutorials/deploy-model)
- [Serverless CLI reference](https://docs.nebius.com/cli/reference/ai/index)
- [Serverless Cookbook](https://github.com/mnrozhkov/serverless-cookbook) for more examples
