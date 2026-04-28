# Live Demo Playbook - User Guide

This playbook runs the whole workshop directly from terminal commands.

## Settings

### 1) Prerequisites and auth

Run `scripts/00_check_prereqs.sh` script to check prerequiists:

```bash
./scripts/00_check_prereqs.sh
```

Is something is missing: 

```bash
command -v nebius && nebius version
command -v aws && aws --version
command -v jq && jq --version
command -v curl && curl --version | head -n 1
command -v ssh
command -v scp 
```

If needed:
- Nebius CLI install: [https://docs.nebius.com/cli](https://docs.nebius.com/cli)
- AWS CLI install: [https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)

Authenticate Nebius and set project context:

```bash
nebius auth login
nebius profile create
# Or if profile already exists:
# nebius config set parent-id <project_id>
```

### 2) Set up environment veriables

Follow the README.md instructions including `2) Preflight checks` to clone repo, set up `.env` file, and create Telegram bot.

Env vars to be set up in `.env`:

```env
# Required secrets
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=

# Optional if Nebius CLI parent-id is not set
PROJECT_ID=
# Optional if you want to pin a specific subnet
SUBNET_ID=

# Runtime values you will fill during the run
BUCKET_NAME=
BUCKET_ID=
FT_RUN_ID=
```

`ENDPOINT_ID`, endpoint URL/token, and VM IP are runtime shell variables in this guide (not `.env` variables).

---

Define static workshop arguments:

```bash
S3_ENDPOINT="https://storage.eu-north1.nebius.cloud"
BUCKET_MOUNT_PATH="/workspace/data"

TRAIN_CONFIG_OBJECT="config.yaml"
TRAIN_DATA_OBJECT="faq_train.jsonl"
TRAIN_OUTPUT_PREFIX="output"

ENDPOINT_NAME="workshop-qwen-endpoint-v2"
ENDPOINT_MODEL="Qwen/Qwen2.5-0.5B"
ENDPOINT_LORA_NAME="qwen-support"
ENDPOINT_CHECKPOINT="checkpoint-50"
```

--- 

Load env:

```bash
set -a; source .env; set +a
```


Resolve project/subnet:

```bash
PROJECT_ID:-$(nebius config get parent-id)}"
SUBNET_ID="$(nebius vpc subnet list --format json | jq -r '.items[0].metadata.id')"
echo "PROJECT_ID=$PROJECT_ID"
echo "SUBNET_ID=$SUBNET_ID"
```

---

### 4) Create object storage + upload training data

Create/configure object storage access and upload training files to the bucket.

```bash
./scripts/10_bootstrap_storage.sh
```

OR do it via web UI as show in the tutorioal:L 
https://docs.nebius.com/serverless/tutorials/fine-tuning#prepare-an-object-storage-bucket  


As a result, you should fill the following env vars in `.env` file and run commands below. 

Env vars: 

```
AWS_KEY_ID=
AWS_KEY_SECRET=
```


Configure AWS CLI:

```bash
aws configure set aws_access_key_id "${AWS_KEY_ID}"
aws configure set aws_secret_access_key "${AWS_KEY_SECRET}"
aws configure set region eu-north1
```

And, upload files:

```bash
aws s3 cp "${TRAIN_CONFIG_OBJECT}" "s3://${BUCKET_NAME}/${TRAIN_CONFIG_OBJECT}" --endpoint-url "${S3_ENDPOINT}"
aws s3 cp "${TRAIN_DATA_OBJECT}" "s3://${BUCKET_NAME}/${TRAIN_DATA_OBJECT}" --endpoint-url "${S3_ENDPOINT}"
aws s3 ls "s3://${BUCKET_NAME}/" --endpoint-url "${S3_ENDPOINT}"
```

---

## 4) Submit fine-tuning job

To run a fine-tuning job, you mount s3 bucket to the Job container (to read config and store fine-tuning results). To make if work, make sure these env vars are set: 

```bash
BUCKET_NAME=
BUCKET_ID=
BUCKET_MOUNT_PATH=/workspace/data  
``` 

Then, run a command to create a fine-tuning job: 

```bash
nebius ai job create \
  --parent-id "$PROJECT_ID" \
  --subnet-id "${SUBNET_ID}" \
  --name "workshop-qwen-finetune-v2" \
  --image "docker.io/axolotlai/axolotl:main-20260309-py3.11-cu128-2.9.1" \
  --platform "gpu-l40s-a" \
  --preset "1gpu-8vcpu-32gb" \
  --disk-size "450Gi" \
  --volume "${BUCKET_ID}:${BUCKET_MOUNT_PATH}" \
  --container-command bash \
  --args '-c "RUN_ID=run-$(date +%Y%m%d-%H%M%S); axolotl train /workspace/data/config.yaml && mkdir -p /workspace/data/output/$RUN_ID && cp -r /workspace/output/. /workspace/data/output/$RUN_ID"'
```

When Job is created, copy it's ID and save to the env var

```bash
JOB_ID=<job_id>
echo "JOB_ID=${JOB_ID}"
```

---

Watch job and get run id:

```bash
nebius ai job logs "${JOB_ID}" --follow
```

The job run a fine-tuninig script and saves checkpoints into a folder names as `run-20260424...`.  This is an generated values used to save the fine-tuning results.

Set `FT_RUN_ID` env var to your run ID. 

```bash
FT_RUN_ID=<run_id>
```

---

## 6) Create serving endpoint (vLLM + LoRA)

```bash
ENDPOINT_AUTH_TOKEN="$(openssl rand -hex 32)"
LORA_PATH="${BUCKET_MOUNT_PATH}/${TRAIN_OUTPUT_PREFIX}/${FT_RUN_ID}/${ENDPOINT_CHECKPOINT}"

EP_JSON="$(nebius ai endpoint create \
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
  --subnet-id "${SUBNET_ID}" \
  --format json)"

ENDPOINT_ID="$(echo "${EP_JSON}" | jq -r '.metadata.id')"
echo "ENDPOINT_ID=${ENDPOINT_ID}"
```

Wait for running + fetch endpoint:

```bash
for _ in {1..60}; do
  E_JSON="$(nebius ai endpoint get "${ENDPOINT_ID}" --format json)"
  E_STATE="$(echo "${E_JSON}" | jq -r '.status.state')"
  ENDPOINT_PUBLIC_ENDPOINT="$(echo "${E_JSON}" | jq -r '.status.public_endpoints[0] // empty')"
  echo "state=${E_STATE} endpoint=${ENDPOINT_PUBLIC_ENDPOINT}"
  [ "${E_STATE}" = "RUNNING" ] && [ -n "${ENDPOINT_PUBLIC_ENDPOINT}" ] && break
  sleep 10
done
```

Smoke test:

```bash
curl -sS "http://${ENDPOINT_PUBLIC_ENDPOINT}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${ENDPOINT_AUTH_TOKEN}" \
  -d "{\"model\":\"${ENDPOINT_LORA_NAME}\",\"messages\":[{\"role\":\"user\",\"content\":\"Does the API support Python 3.12?\"}]}" \
  | jq -r '.choices[0].message.content // .'
```

---

## 7) Create CPU VM for OpenClaw

```bash
CPU_VM_NAME="openclaw-cpu-vm-1"
CPU_DISK_NAME="openclaw-cpu-disk-1"
CPU_DISK_GB="60"
CPU_IMAGE_FAMILY="ubuntu24.04-driverless"
CPU_VM_USER="user"
```

Ensure SSH key exists:

```bash
[ -f "$HOME/.ssh/id_ed25519.pub" ] || ssh-keygen -t ed25519
```

Create disk + VM:

```bash
DISK_ID="$(nebius compute disk get-by-name --name "${CPU_DISK_NAME}" --parent-id "${PROJECT_ID}" --format jsonpath='{.metadata.id}' 2>/dev/null || true)"
if [ -z "${DISK_ID}" ]; then
  DISK_ID="$(nebius compute disk create \
    --name "${CPU_DISK_NAME}" \
    --size-gibibytes "${CPU_DISK_GB}" \
    --type network_ssd \
    --source-image-family-image-family "${CPU_IMAGE_FAMILY}" \
    --block-size-bytes 4096 \
    --format json | jq -r '.metadata.id')"
fi

USER_DATA="$(cat <<EOF
users:
  - name: ${CPU_VM_USER}
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - $(cat "$HOME/.ssh/id_ed25519.pub")
EOF
)"
USER_DATA_JSON="$(printf '%s' "${USER_DATA}" | jq -Rs .)"

SPEC="$(cat <<EOF
{
  "metadata": { "name": "${CPU_VM_NAME}" },
  "spec": {
    "stopped": false,
    "cloud_init_user_data": ${USER_DATA_JSON},
    "resources": { "platform": "cpu-d3", "preset": "4vcpu-16gb" },
    "boot_disk": { "attach_mode": "READ_WRITE", "existing_disk": { "id": "${DISK_ID}" } },
    "network_interfaces": [
      { "name": "openclaw-if0", "subnet_id": "${SUBNET_ID}", "ip_address": {}, "public_ip_address": {} }
    ]
  }
}
EOF
)"

INSTANCE_ID="$(printf '%s' "${SPEC}" | nebius compute instance create --format json - | jq -r '.metadata.id')"
CPU_VM_IP="$(nebius compute instance get --id "${INSTANCE_ID}" --format json | jq -r '.status.network_interfaces[0].public_ip_address.address | split("/")[0]')"
echo "CPU_VM_IP=${CPU_VM_IP}"
```

---

## 8) Install OpenClaw on VM

```bash
ssh -o StrictHostKeyChecking=accept-new "${CPU_VM_USER}@${CPU_VM_IP}" \
  'curl -fsSL https://openclaw.ai/install.sh | OPENCLAW_VERSION=2026.1.29 bash'

ssh "${CPU_VM_USER}@${CPU_VM_IP}" \
  'echo '\''export PATH="$HOME/.npm-global/bin:$PATH"'\'' >> ~/.bashrc'

ssh "${CPU_VM_USER}@${CPU_VM_IP}" \
  'export PATH="$HOME/.npm-global/bin:$PATH"; openclaw config set gateway.mode local; openclaw daemon install; openclaw daemon restart; openclaw daemon status'
```

---

## 9) Configure OpenClaw model provider to your endpoint

```bash
ENDPOINT_HOSTPORT="${ENDPOINT_PUBLIC_ENDPOINT}"
OPENCLAW_MODEL="nebius/qwen-support"

ssh "${CPU_VM_USER}@${CPU_VM_IP}" "export PATH=\"\$HOME/.npm-global/bin:\$PATH\"; \
CONFIG_FILE=\"\$HOME/.openclaw/config.json\"; \
mkdir -p \"\$(dirname \$CONFIG_FILE)\"; \
if [[ -f \"\$CONFIG_FILE\" ]]; then \
  tmp=\$(mktemp); jq '.gateway.mode = \"local\"' \"\$CONFIG_FILE\" > \"\$tmp\" && mv \"\$tmp\" \"\$CONFIG_FILE\"; \
else \
  echo '{\"gateway\":{\"mode\":\"local\"}}' > \"\$CONFIG_FILE\"; \
fi; \
openclaw config set models.providers.nebius --strict-json '{\"baseUrl\":\"http://${ENDPOINT_HOSTPORT}/v1\",\"api\":\"openai-completions\",\"apiKey\":\"${ENDPOINT_AUTH_TOKEN}\",\"models\":[{\"id\":\"qwen-support\",\"name\":\"qwen-support\",\"api\":\"openai-completions\",\"maxTokens\":256,\"contextWindow\":32768}]}' && \
openclaw models set ${OPENCLAW_MODEL} && \
openclaw daemon restart && \
openclaw models status --json"
```

---

## 10) Run triage remotely and get outputs

```bash
REMOTE_DIR="~/nebius-openclaw-workshop"
OPENCLAW_BIN="/home/user/.npm-global/bin/openclaw"
OPENCLAW_SESSION_FILE="/home/user/.openclaw/agents/main/sessions/sessions.json"
TRIAGE_TIMEOUT_SEC="20"

ssh "${CPU_VM_USER}@${CPU_VM_IP}" "mkdir -p ${REMOTE_DIR}"
scp support_tickets.csv "${CPU_VM_USER}@${CPU_VM_IP}:${REMOTE_DIR}/support_tickets.csv"
scp scripts/triage_runner.py "${CPU_VM_USER}@${CPU_VM_IP}:${REMOTE_DIR}/triage_runner.py"

ssh -T "${CPU_VM_USER}@${CPU_VM_IP}" "\
export WORKSHOP_DIR=${REMOTE_DIR}; \
export OPENCLAW_BIN='${OPENCLAW_BIN}'; \
export OPENCLAW_MODEL='${OPENCLAW_MODEL}'; \
export OPENCLAW_SESSION_FILE='${OPENCLAW_SESSION_FILE}'; \
export TRIAGE_TIMEOUT_SEC='${TRIAGE_TIMEOUT_SEC}'; \
export TELEGRAM_BOT_TOKEN='${TELEGRAM_BOT_TOKEN}'; \
export TELEGRAM_CHAT_ID='${TELEGRAM_CHAT_ID}'; \
python3 ${REMOTE_DIR}/triage_runner.py"
```

Expected outputs on VM:
- `~/nebius-openclaw-workshop/triage_results_telegram.json`
- `~/nebius-openclaw-workshop/triage_results_telegram.csv`

Optional copy back locally:

```bash
scp "${CPU_VM_USER}@${CPU_VM_IP}:~/nebius-openclaw-workshop/triage_results_telegram.json" .
scp "${CPU_VM_USER}@${CPU_VM_IP}:~/nebius-openclaw-workshop/triage_results_telegram.csv" .
```

---

## Backup: script equivalents

If any direct command step fails, equivalent scripts are:

```bash
./scripts/00_check_prereqs.sh
./scripts/10_bootstrap_storage.sh
./scripts/20_submit_finetune_job.sh
./scripts/21_watch_finetune_job.sh <job_id>
./scripts/30_create_endpoint.sh
./scripts/31_wait_and_test_endpoint.sh <endpoint_id> <auth_token>
./scripts/40_create_cpu_vm.sh
./scripts/41_install_openclaw_remote.sh <vm_public_ip>
./scripts/42_configure_openclaw_remote.sh <vm_public_ip> <endpoint_hostport> <endpoint_token>
./scripts/50_run_triage_remote.sh <vm_public_ip>
```