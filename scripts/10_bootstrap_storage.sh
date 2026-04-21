#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

load_env
require_cmd nebius
require_cmd aws
require_cmd jq

PROJECT_ID="$(resolve_project_id)"
BUCKET_NAME="${BUCKET_NAME:?BUCKET_NAME is required}"
TRAIN_CONFIG_OBJECT="${TRAIN_CONFIG_OBJECT:-config.yaml}"
TRAIN_DATA_OBJECT="${TRAIN_DATA_OBJECT:-faq_train.jsonl}"

# Register the bucket in the project (Nebius control plane). `aws s3 mb` alone talks only to the S3
# API and often does not show up under the project's Object Storage in the console; `nebius storage
# bucket get-by-name` (used by training scripts) also expects this resource.
if ! nebius storage bucket get-by-name --name "$BUCKET_NAME" --parent-id "$PROJECT_ID" --format json >/dev/null 2>&1; then
  nebius storage bucket create --name "$BUCKET_NAME" --parent-id "$PROJECT_ID"
fi

SA_NAME="object-storage-sa-workshop"
TENANT_ID="$(nebius iam project get "$PROJECT_ID" --format json | json_get '.metadata.parent_id')"
EDITORS_GROUP_ID="$(nebius iam group get-by-name --name editors --parent-id "$TENANT_ID" --format json | json_get '.metadata.id')"

SA_ID="$(nebius iam service-account get-by-name --name "$SA_NAME" --parent-id "$PROJECT_ID" --format jsonpath='{.metadata.id}' 2>/dev/null || true)"
if [[ -z "$SA_ID" ]]; then
  SA_ID="$(nebius iam service-account create --name "$SA_NAME" --parent-id "$PROJECT_ID" --format jsonpath='{.metadata.id}')"
  nebius iam group-membership create --parent-id "$EDITORS_GROUP_ID" --member-id "$SA_ID" >/dev/null
fi

ACCESS_KEY_ID="$(nebius iam access-key create --account-service-account-id "$SA_ID" --description 'AWS CLI workshop' --format jsonpath='{.resource_id}')"
AWS_ACCESS_KEY_ID="$(nebius iam access-key get-by-id --id "$ACCESS_KEY_ID" --format json | json_get '.status.aws_access_key_id')"
AWS_SECRET_ACCESS_KEY="$(nebius iam access-key get-secret-once --id "$ACCESS_KEY_ID" --format json | json_get '.secret')"

aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
aws configure set region eu-north1
aws configure set endpoint_url https://storage.eu-north1.nebius.cloud

if ! aws s3 ls "s3://$BUCKET_NAME" >/dev/null 2>&1; then
  aws s3 mb "s3://$BUCKET_NAME"
fi

if [[ -f "$ROOT_DIR/../$TRAIN_CONFIG_OBJECT" ]]; then
  aws s3 cp "$ROOT_DIR/../$TRAIN_CONFIG_OBJECT" "s3://$BUCKET_NAME/$TRAIN_CONFIG_OBJECT"
fi

if [[ -f "$ROOT_DIR/../$TRAIN_DATA_OBJECT" ]]; then
  aws s3 cp "$ROOT_DIR/../$TRAIN_DATA_OBJECT" "s3://$BUCKET_NAME/$TRAIN_DATA_OBJECT"
fi

echo "storage_bootstrap_done=true"
echo "project_id=$PROJECT_ID"
echo "storage_bucket_id=$STORAGE_BUCKET_ID"
echo "service_account_id=$SA_ID"
echo "bucket=$BUCKET_NAME"
aws s3 ls "s3://$BUCKET_NAME/"
