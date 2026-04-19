# 50-Min Live Demo Playbook (Beginner-Friendly + Runnable)

This is the **manual-first** workshop flow.  
Use scripts only as fallback/takeaway.

## Format

- Audience sees real commands and outputs.
- You keep momentum with pre-defined recovery commands.
- Time target: 50 minutes.

---

## Before Session (Do this once)

1. In terminal:

```bash
git clone https://github.com/MarouaneKhoukh/nebius-openclaw-workshop.git
cd nebius-openclaw-workshop
cp .env.example .env
```

2. Fill `.env` with:
- `NEBIUS_PROJECT_ID`
- `BUCKET_NAME=workshop-llm`
- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_CHAT_ID`

3. Run prereq check:

```bash
./scripts/00_check_prereqs.sh
```

4. Keep these files ready in `../`:
- `config.yaml`
- `faq_train.jsonl`
- `support_tickets.csv`

---

## 0:00-0:05 Setup + Story

Show:

```bash
nebius version
aws --version
jq --version
```

Say: we’ll fine-tune, deploy, then automate triage.

---

## 0:05-0:18 Phase 1 Fine-tune

### A) Bootstrap object storage + upload data

```bash
./scripts/10_bootstrap_storage.sh
```

Expected:
- bucket exists
- `config.yaml` and `faq_train.jsonl` in bucket listing

### B) Submit job

```bash
./scripts/20_submit_finetune_job.sh
```

Copy `job_id=...`

### C) Watch progress

```bash
./scripts/21_watch_finetune_job.sh <job_id>
```

Expected:
- `state=COMPLETED`
- latest `run-...` printed

Set run id in `.env`:
- `ENDPOINT_RUN_ID=run-YYYYMMDD-HHMMSS`

---

## 0:18-0:30 Phase 2 Deploy Endpoint

### A) Create endpoint

```bash
./scripts/30_create_endpoint.sh
```

Copy:
- `endpoint_id`
- `public_endpoint` (`host:port`)
- `auth_token`

### B) Wait + test

```bash
./scripts/31_wait_and_test_endpoint.sh <endpoint_id> <auth_token>
```

Expected:
- endpoint reaches `RUNNING`
- returns answer text for Python question

### C) Manual direct check (show OpenAI format)

```bash
curl -s "http://<public_endpoint>/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <auth_token>" \
  -d '{"model":"qwen-support","messages":[{"role":"user","content":"What is the price of the Pro plan?"}]}' | jq -r '.choices[0].message.content'
```

---

## 0:30-0:45 Phase 3 OpenClaw + Triage

### A) Create CPU VM

```bash
./scripts/40_create_cpu_vm.sh
```

Copy `public_ip`.

### B) Install OpenClaw on VM

```bash
./scripts/41_install_openclaw_remote.sh <vm_public_ip>
```

### C) Configure OpenClaw -> Nebius endpoint

```bash
./scripts/42_configure_openclaw_remote.sh <vm_public_ip> <public_endpoint> <auth_token>
```

### D) Run triage + Telegram escalation

```bash
./scripts/50_run_triage_remote.sh <vm_public_ip>
```

Expected:
- per-ticket logs
- `answered=...`
- `escalated=...`
- Telegram messages for escalated tickets

---

## 0:45-0:50 Wrap-up

Show output artifacts on VM (`~/nebius-openclaw-workshop`):
- `triage_results_telegram.json`
- `triage_results_telegram.csv`

Narrative:
- same architecture, different data
- small model + specific domain can beat generic quality on narrow tasks
- next step: two-way human loop from Telegram reply back into ticket system

---

## Fast Recovery (Use exactly as needed)

### 1) Endpoint says STARTING too long

```bash
nebius ai endpoint get <endpoint_id> --format json | jq '.status'
```

If still unstable, recreate endpoint with:
- `--enable-auto-tool-choice`
- `--tool-call-parser hermes`

(already baked into `30_create_endpoint.sh`)

### 2) Direct curl works but OpenClaw fails with tool payload/schema

Cause: endpoint missing tool-choice flags.  
Fix: recreate endpoint via `30_create_endpoint.sh` (v2 style).

### 3) OpenClaw returns context overflow / degraded outputs

Cause: session history accumulation.  
Fix: stateless per-ticket calls (already in `triage_runner.py`):
- deletes session file each ticket
- short timeout

### 4) Telegram `getUpdates` empty

- Ensure you message the bot directly (`/start`, then `hello`)
- Ensure webhook deleted:

```bash
curl -s "https://api.telegram.org/bot<TOKEN>/deleteWebhook?drop_pending_updates=true"
curl -s "https://api.telegram.org/bot<TOKEN>/getUpdates"
```

### 5) Token format invalid

Must look like:
- `123456789:AA...`

If 404 from Telegram API, token is wrong/truncated.

### 6) SSH refused right after VM create

Wait 30-90s and retry:

```bash
ssh -o StrictHostKeyChecking=accept-new user@<vm_public_ip> 'echo ok'
```

---

## Presenter Tips

- If time is tight, start fine-tuning 10-15 min before session.
- Keep one known-good endpoint running as fallback.
- For audience confidence, always show one direct endpoint curl before OpenClaw.
- Treat scripts as “reliable ops mode,” but keep command visibility in demo.
