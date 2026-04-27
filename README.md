# Workshop: Fine-Tune, Serve, and Triage with OpenClaw

In this workshop, participants will build a complete support-triage flow:

- Fine-tune `Qwen2.5-0.5B` on FAQ data
- Deploy a Nebius endpoint with LoRA
- Run OpenClaw on a CPU VM
- Auto-answer tickets and escalate failures to Telegram

## Workshop Runbook 

### 1) Clone and prepare env

Set up the local workshop folder and create your editable `.env` file.

```bash
git clone https://github.com/MarouaneKhoukh/nebius-openclaw-workshop.git
cd nebius-openclaw-workshop
cp .env.example .env
```

## Telegram Setup 

1. Create a bot with BotFather:
   - Open Telegram and search `@BotFather`
   - Send `/newbot`
   - Copy the bot token (format looks like `123456789:AA...`)

2. Start chat with your bot:
   - Open your bot chat (for example `https://t.me/<your_bot_username>`)
   - Press **Start**
   - Send one message, e.g. `hello`

3. Get your chat id:

```bash
curl -s "https://api.telegram.org/bot<BOT_TOKEN>/deleteWebhook?drop_pending_updates=true"
curl -s "https://api.telegram.org/bot<BOT_TOKEN>/getUpdates"
```

From the JSON output, copy:

```json
"chat":{"id":123456789,...}
```

4. Put both in `.env`:

```env
TELEGRAM_BOT_TOKEN=<BOT_TOKEN>
TELEGRAM_CHAT_ID=<CHAT_ID>
```

5. Optional test:

```bash
curl -s "https://api.telegram.org/bot<BOT_TOKEN>/sendMessage" \
  -d "chat_id=<CHAT_ID>" \
  -d "text=Workshop Telegram test"
```

### 2) Preflight checks

Verify CLI tools, Nebius authentication, project id, and subnet are available.

```bash
./scripts/00_check_prereqs.sh
```

### 3) Upload config + data to object storage

Create/configure object storage access and upload training files to the bucket.

```bash
./scripts/10_bootstrap_storage.sh
```

### 4) Submit fine-tuning job

Start the GPU Axolotl job that trains LoRA weights from your FAQ dataset.

```bash
./scripts/20_submit_finetune_job.sh
```

Copy `job_id=...` from output.

### 5) Watch training until completion

Track job state until completion and identify the generated `run-...` output folder.

```bash
./scripts/21_watch_finetune_job.sh <job_id>
```

When completed, set `ENDPOINT_RUN_ID=run-...` in `.env`.

### 6) Create endpoint

Deploy a vLLM endpoint that serves base Qwen + your LoRA adapter.

```bash
./scripts/30_create_endpoint.sh
```

Copy:
- `endpoint_id`
- `public_endpoint`
- `auth_token`

### 7) Wait for endpoint and test response

Wait for endpoint readiness and run a direct inference smoke test.

```bash
./scripts/31_wait_and_test_endpoint.sh <endpoint_id> <auth_token>
```

### 8) Create CPU VM for OpenClaw

Provision a CPU VM that will run OpenClaw orchestration.

```bash
./scripts/40_create_cpu_vm.sh
```

Copy `public_ip`.

### 9) Install OpenClaw on VM

Install OpenClaw remotely and start its background daemon service.

```bash
./scripts/41_install_openclaw_remote.sh <vm_public_ip>
```

### 10) Configure OpenClaw + run triage

Point OpenClaw to your Nebius endpoint, then process tickets and escalate failures to Telegram.

```bash
./scripts/42_configure_openclaw_remote.sh <vm_public_ip> <endpoint_hostport> <endpoint_token>
./scripts/50_run_triage_remote.sh <vm_public_ip>
```

Expected outputs on VM (`~/nebius-openclaw-workshop`):

- `triage_results_telegram.json`
- `triage_results_telegram.csv`
