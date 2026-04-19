#!/usr/bin/env python3
import csv
import json
import os
import re
import subprocess
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import urlopen

WORKDIR = Path(os.environ.get("WORKSHOP_DIR", str(Path.home() / "workshop-openclaw")))
OPENCLAW_BIN = os.environ.get("OPENCLAW_BIN", "/home/user/.npm-global/bin/openclaw")
OPENCLAW_MODEL = os.environ.get("OPENCLAW_MODEL", "nebius/qwen-support")
SESSION_FILE = Path(os.environ.get("OPENCLAW_SESSION_FILE", str(Path.home() / ".openclaw/agents/main/sessions/sessions.json")))
TIMEOUT_SEC = int(os.environ.get("TRIAGE_TIMEOUT_SEC", "20"))

TELEGRAM_BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
TELEGRAM_CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "")


def should_escalate(text: str) -> bool:
    t = (text or "").strip().lower()
    if not t:
        return True
    fail = ["error:", "timeout", "context overflow", "provider rejected", "llm request failed"]
    if any(x in t for x in fail):
        return True
    if re.search(r"(assistant\s*){6,}", t):
        return True
    return False


def send_telegram(text: str) -> bool:
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        return False
    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
    body = urlencode({"chat_id": TELEGRAM_CHAT_ID, "text": text}).encode("utf-8")
    try:
        with urlopen(url, data=body, timeout=15) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
            return bool(payload.get("ok"))
    except Exception:
        return False


def ask(prompt: str) -> str:
    SESSION_FILE.unlink(missing_ok=True)
    cmd = [
        OPENCLAW_BIN, "infer", "model", "run",
        "--local", "--json",
        "--model", OPENCLAW_MODEL,
        "--prompt", prompt,
    ]
    try:
        p = subprocess.run(cmd, cwd=WORKDIR, capture_output=True, text=True, timeout=TIMEOUT_SEC)
    except subprocess.TimeoutExpired:
        return "ERROR: timeout"
    if p.returncode != 0:
        return f"ERROR: {(p.stderr or p.stdout).strip()}"
    try:
        j = json.loads(p.stdout)
        return ((j.get("outputs") or [{}])[0].get("text") or "").strip()
    except Exception:
        return p.stdout.strip()


def main() -> int:
    tickets_file = WORKDIR / "support_tickets.csv"
    out_json = WORKDIR / "triage_results_telegram.json"
    out_csv = WORKDIR / "triage_results_telegram.csv"

    results = []
    with tickets_file.open() as f:
        for row in csv.DictReader(f):
            answer = ask(row["question"])
            action = "escalated" if should_escalate(answer) else "answered"
            sent = False
            if action == "escalated":
                msg = (
                    f"[Escalated] Ticket {row['ticket_id']}\n"
                    f"Customer: {row['customer_name']}\n"
                    f"Question: {row['question']}\n"
                    f"Model output: {answer[:500]}"
                )
                sent = send_telegram(msg)
            rec = {
                "ticket_id": row["ticket_id"],
                "customer_name": row["customer_name"],
                "question": row["question"],
                "model_answer": answer,
                "action": action,
                "telegram_sent": sent,
            }
            results.append(rec)
            print(f"{row['ticket_id']}|{action}|telegram={sent}|{answer[:120]}", flush=True)

    answered = sum(1 for r in results if r["action"] == "answered")
    escalated = sum(1 for r in results if r["action"] == "escalated")

    out_json.write_text(json.dumps({"answered": answered, "escalated": escalated, "results": results}, indent=2))
    with out_csv.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["ticket_id", "customer_name", "question", "model_answer", "action", "telegram_sent"])
        writer.writeheader()
        writer.writerows(results)

    send_telegram(f"Triage run complete: answered={answered}, escalated={escalated}")
    print(f"answered={answered}")
    print(f"escalated={escalated}")
    print(f"results_json={out_json}")
    print(f"results_csv={out_csv}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
