# Workshop: Fine-Tune, Serve, and Triage with OpenClaw

In this workshop, participants will build a complete support-triage flow:

- Fine-tune `Qwen2.5-0.5B` on FAQ data
- Deploy a Nebius endpoint with LoRA
- Run OpenClaw on a CPU VM
- Auto-answer tickets and escalate failures to Telegram

## Workshop Runbook (Single Path)

### 1) Clone and prepare env

```bash
git clone https://github.com/MarouaneKhoukh/nebius-openclaw-workshop.git
cd nebius-openclaw-workshop
cp .env.example .env
```

## Telegram Setup (5 Minutes)

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

```bash
./scripts/00_check_prereqs.sh
```

### 3) Upload config + data to object storage

```bash
./scripts/10_bootstrap_storage.sh
```

### 4) Submit fine-tuning job

```bash
./scripts/20_submit_finetune_job.sh
```

Copy `job_id=...` from output.

### 5) Watch training until completion

```bash
./scripts/21_watch_finetune_job.sh <job_id>
```

When completed, set `ENDPOINT_RUN_ID=run-...` in `.env`.

### 6) Create endpoint

```bash
./scripts/30_create_endpoint.sh
```

Copy:
- `endpoint_id`
- `public_endpoint`
- `auth_token`

### 7) Wait for endpoint and test response

```bash
./scripts/31_wait_and_test_endpoint.sh <endpoint_id> <auth_token>
```

### 8) Create CPU VM for OpenClaw

```bash
./scripts/40_create_cpu_vm.sh
```

Copy `public_ip`.

### 9) Install OpenClaw on VM

```bash
./scripts/41_install_openclaw_remote.sh <vm_public_ip>
```

### 10) Configure OpenClaw + run triage

```bash
./scripts/42_configure_openclaw_remote.sh <vm_public_ip> <endpoint_hostport> <endpoint_token>
./scripts/50_run_triage_remote.sh <vm_public_ip>
```

Expected outputs on VM (`~/nebius-openclaw-workshop`):
- `triage_results_telegram.json`
- `triage_results_telegram.csv`

## Why this kit is stable for live demos

- Stateless inference per ticket (session file reset each ticket)
- Short per-ticket timeout to avoid long hangs
- Escalation only on hard failures (`timeout`, `error`, overflow-like outputs)
- Endpoint created with tool parser + auto tool choice flags

## Troubleshooting (By Error)

| Symptom | Likely Cause | Fix |
|---|---|---|
| `502 Bad Gateway` on endpoint | vLLM still booting or bad args | Wait, then re-run endpoint check. If persistent, recreate endpoint with `30_create_endpoint.sh`. |
| OpenClaw error mentions `tool_choice` / schema | Endpoint missing tool-call compatibility flags | Recreate endpoint using this kit (flags are built-in in `30_create_endpoint.sh`). |
| `Context overflow` from OpenClaw path | Session context accumulation | Keep stateless runner (already built into `triage_runner.py`). |
| `ssh ... connection refused` right after VM create | Cloud-init not finished | Wait 30-90 seconds, retry SSH. |
| Telegram `{"ok":true,"result":[]}` from `getUpdates` | No message received by bot yet | Send `/start` to bot, then `hello`, then call `getUpdates` again. |
| Telegram `404 Not Found` | Invalid/truncated bot token | Use full token format `123456:AA...` from BotFather. |
| `openclaw: command not found` on VM | PATH not updated | Use `/home/user/.npm-global/bin/openclaw` or re-run `41_install_openclaw_remote.sh`. |

## Participant-visible Assets

- `scripts/` contains all runnable automation
- `LIVE_DEMO_PLAYBOOK.md` contains command-by-command presenter flow
- `triage_runner.py` shows the exact triage + escalation logic
