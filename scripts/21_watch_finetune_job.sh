#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

load_env
require_cmd nebius
require_cmd aws
require_cmd jq

JOB_ID="${1:-}"
if [[ -z "$JOB_ID" ]]; then
  JOB_ID="$(nebius ai job get-by-name --name "$TRAIN_JOB_NAME" --format jsonpath='{.metadata.id}')"
fi

echo "watching_job_id=$JOB_ID"

for _ in {1..120}; do
  STATE="$(nebius ai job get "$JOB_ID" --format json | json_get '.status.state')"
  echo "state=$STATE"
  if [[ "$STATE" == "COMPLETED" ]]; then
    break
  fi
  if [[ "$STATE" == "FAILED" || "$STATE" == "CANCELLED" ]]; then
    echo "job_failed=true"
    nebius ai job logs "$JOB_ID" | tail -n 200 || true
    exit 1
  fi
  sleep 15
done

LATEST_RUN="$(aws s3 ls "s3://$BUCKET_NAME/$TRAIN_OUTPUT_PREFIX/" | awk '{print $2}' | sed 's#/##' | grep '^run-' | sort | tail -n1 || true)"
if [[ -n "$LATEST_RUN" ]]; then
  echo "latest_run_id=$LATEST_RUN"
  aws s3 ls "s3://$BUCKET_NAME/$TRAIN_OUTPUT_PREFIX/$LATEST_RUN/" --recursive | tail -n 20
fi
