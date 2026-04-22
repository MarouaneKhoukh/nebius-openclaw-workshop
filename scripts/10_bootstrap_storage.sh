#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

load_env
require_cmd nebius
require_cmd aws
require_cmd jq

PROJECT_ID="$(resolve_project_id)"
TRAIN_CONFIG_OBJECT="${TRAIN_CONFIG_OBJECT:-config.yaml}"
TRAIN_DATA_OBJECT="${TRAIN_DATA_OBJECT:-faq_train.jsonl}"
S3_ENDPOINT="https://storage.eu-north1.nebius.cloud"

# Auto-generate a unique bucket name if not set.
# Uses a random suffix so re-runs on the same project never collide.
if [[ -z "${BUCKET_NAME:-}" || "${BUCKET_NAME:-}" == "workshop-llm" ]]; then
  RAND_SUFFIX="$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c6)"
  BUCKET_NAME="workshop-llm-${RAND_SUFFIX}"
  ENV_FILE="$(cd "$(dirname "$0")" && pwd)/../.env"
  if grep -q "^BUCKET_NAME=" "$ENV_FILE" 2>/dev/null; then
    sed -i.bak "s|^BUCKET_NAME=.*|BUCKET_NAME=$BUCKET_NAME|" "$ENV_FILE" && rm -f "$ENV_FILE.bak"
  else
    echo "BUCKET_NAME=$BUCKET_NAME" >> "$ENV_FILE"
  fi
  echo "  ℹ  Auto-generated bucket name: $BUCKET_NAME (saved to .env)"
fi

# ── Register bucket in Nebius control plane ─────────────
# This makes it visible in the console AND accessible by training jobs.
# Must use nebius CLI here — aws s3 mb only hits the S3 API and won't show in console.
echo "── Setting up object storage ──────────────────────"
if ! nebius storage bucket get-by-name \
     --name "$BUCKET_NAME" \
     --parent-id "$PROJECT_ID" \
     --format json >/dev/null 2>&1; then
  echo "  Creating bucket: $BUCKET_NAME"
  nebius storage bucket create \
    --name "$BUCKET_NAME" \
    --parent-id "$PROJECT_ID"
  echo "  ✓ Bucket created: $BUCKET_NAME"
else
  echo "  ✓ Bucket already exists: $BUCKET_NAME"
fi

# ── Create service account + access key ─────────────────
SA_NAME="object-storage-sa-workshop"
TENANT_ID="$(nebius iam project get "$PROJECT_ID" --format json | json_get '.metadata.parent_id')"
EDITORS_GROUP_ID="$(nebius iam group get-by-name --name editors --parent-id "$TENANT_ID" --format json | json_get '.metadata.id')"

SA_ID="$(nebius iam service-account get-by-name \
  --name "$SA_NAME" \
  --parent-id "$PROJECT_ID" \
  --format jsonpath='{.metadata.id}' 2>/dev/null || true)"

if [[ -z "$SA_ID" ]]; then
  echo "  Creating service account: $SA_NAME"
  SA_ID="$(nebius iam service-account create \
    --name "$SA_NAME" \
    --parent-id "$PROJECT_ID" \
    --format jsonpath='{.metadata.id}')"
  nebius iam group-membership create \
    --parent-id "$EDITORS_GROUP_ID" \
    --member-id "$SA_ID" >/dev/null
  echo "  ✓ Service account created: $SA_ID"
else
  echo "  ✓ Service account exists: $SA_ID"
fi

# FIX: use v2 API — old access-key command returns plain string for secret, not JSON
echo "  Creating access key..."
ACCESS_KEY_JSON="$(nebius iam v2 access-key create \
  --account-service-account-id "$SA_ID" \
  --description 'AWS CLI workshop' \
  --format json)"

AWS_KEY_ID="$(echo "$ACCESS_KEY_JSON"   | jq -r '.status.aws_access_key_id')"
AWS_KEY_SECRET="$(echo "$ACCESS_KEY_JSON" | jq -r '.status.secret')"
echo "  ✓ Access key created"

# ── Configure AWS CLI ────────────────────────────────────
# FIX: do NOT use `aws configure set endpoint_url` — causes 'str has no attribute get' parse error.
# Pass --endpoint-url explicitly on every aws s3 call instead.
aws configure set aws_access_key_id     "$AWS_KEY_ID"
aws configure set aws_secret_access_key "$AWS_KEY_SECRET"
aws configure set region eu-north1
echo "  ✓ AWS CLI configured for Nebius S3"

# ── Upload training files ────────────────────────────────
echo ""
echo "── Uploading training files ───────────────────────"

# Look in repo root (where files actually live)
for search_path in "$ROOT_DIR" "$ROOT_DIR/.."; do
  if [[ -f "$search_path/$TRAIN_CONFIG_OBJECT" ]]; then
    aws s3 cp "$search_path/$TRAIN_CONFIG_OBJECT" \
      "s3://$BUCKET_NAME/$TRAIN_CONFIG_OBJECT" \
      --endpoint-url "$S3_ENDPOINT"
    echo "  ✓ Uploaded $TRAIN_CONFIG_OBJECT"
    break
  fi
done

for search_path in "$ROOT_DIR" "$ROOT_DIR/.."; do
  if [[ -f "$search_path/$TRAIN_DATA_OBJECT" ]]; then
    aws s3 cp "$search_path/$TRAIN_DATA_OBJECT" \
      "s3://$BUCKET_NAME/$TRAIN_DATA_OBJECT" \
      --endpoint-url "$S3_ENDPOINT"
    echo "  ✓ Uploaded $TRAIN_DATA_OBJECT"
    break
  fi
done

# ── Verify ───────────────────────────────────────────────
echo ""
echo "── Bucket contents ────────────────────────────────"
aws s3 ls "s3://$BUCKET_NAME/" --endpoint-url "$S3_ENDPOINT"

echo ""
echo "storage_bootstrap_done=true"
echo "project_id=$PROJECT_ID"
echo "storage_bucket_id=$STORAGE_BUCKET_ID"
echo "service_account_id=$SA_ID"
echo "bucket=$BUCKET_NAME"