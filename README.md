# Workshop: Fine-Tune, Serve, and Triage with OpenClaw

In this workshop, participants will build a complete support-triage flow:

- Fine-tune `Qwen2.5-0.5B` on FAQ data
- Deploy a Nebius endpoint with LoRA
- Run OpenClaw on a CPU VM
- Auto-answer tickets and escalate failures to Telegram

## Quickstart (10 Commands)

Run from:

```bash
cd /Users/marouanekhoukh/Documents/Playground/workshop-openclaw/from-scratch
```

1.
```bash
cp .env.workshop.sample .env
```
2.
```bash
./scripts/00_check_prereqs.sh
```
3.
```bash
./scripts/10_bootstrap_storage.sh
```
4.
```bash
./scripts/20_submit_finetune_job.sh
```
5.
```bash
./scripts/21_watch_finetune_job.sh <job_id>
```
6.
```bash
./scripts/30_create_endpoint.sh
```
7.
```bash
./scripts/31_wait_and_test_endpoint.sh <endpoint_id> <auth_token>
```
8.
```bash
./scripts/40_create_cpu_vm.sh
```
9.
```bash
./scripts/41_install_openclaw_remote.sh <vm_public_ip>
```
10.
```bash
./scripts/42_configure_openclaw_remote.sh <vm_public_ip> <endpoint_hostport> <endpoint_token> && ./scripts/50_run_triage_remote.sh <vm_public_ip>
```

Outputs on VM:

- `~/workshop-openclaw/triage_results_telegram.json`
- `~/workshop-openclaw/triage_results_telegram.csv`

## Workshop Flow

1. **Prepare env**
   - Use `.env.workshop.sample` as the base.
   - Fill:
     - `NEBIUS_PROJECT_ID`
     - `TELEGRAM_BOT_TOKEN`
     - `TELEGRAM_CHAT_ID`

2. **Upload data + config**
   - `10_bootstrap_storage.sh` uploads `config.yaml` + `faq_train.jsonl` from `../`.

3. **Train**
   - `20_submit_finetune_job.sh` starts the Axolotl job.
   - `21_watch_finetune_job.sh` waits and reports latest `run-...`.
   - Put that run in `.env` as `ENDPOINT_RUN_ID`.

4. **Serve**
   - `30_create_endpoint.sh` creates vLLM endpoint with:
     - LoRA module mounted from object storage
     - tool-choice flags needed for OpenClaw compatibility
   - `31_wait_and_test_endpoint.sh` confirms live responses.

5. **Orchestrate**
   - `40_create_cpu_vm.sh` provisions CPU VM.
   - `41_install_openclaw_remote.sh` installs and starts OpenClaw.
   - `42_configure_openclaw_remote.sh` points OpenClaw to Nebius endpoint.

6. **Run triage**
   - `50_run_triage_remote.sh` copies `support_tickets.csv` and runs triage.
   - Escalated tickets are sent to Telegram.

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
