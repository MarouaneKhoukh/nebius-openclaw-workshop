#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

# ──────────────────────────────────────────────
# Auto-install helpers
# ──────────────────────────────────────────────

OS="$(uname -s)"

install_aws() {
  echo "  → Installing AWS CLI..."
  if [[ "$OS" == "Darwin" ]]; then
    if command -v brew >/dev/null 2>&1; then
      brew install awscli
    else
      curl -fsSL "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o /tmp/AWSCLIV2.pkg
      sudo installer -pkg /tmp/AWSCLIV2.pkg -target /
      rm /tmp/AWSCLIV2.pkg
    fi
  elif [[ "$OS" == "Linux" ]]; then
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    unzip -q /tmp/awscliv2.zip -d /tmp/awscli-install
    sudo /tmp/awscli-install/aws/install --update
    rm -rf /tmp/awscliv2.zip /tmp/awscli-install
  else
    echo "  ✗ Unsupported OS for auto-install: $OS"
    echo "    Install manually: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
    exit 1
  fi
  echo "  ✓ aws installed: $(aws --version 2>&1)"
}

install_jq() {
  echo "  → Installing jq..."
  if [[ "$OS" == "Darwin" ]]; then
    if command -v brew >/dev/null 2>&1; then
      brew install jq
    else
      echo "  ✗ Homebrew not found. Install jq manually: https://stedolan.github.io/jq/download/"
      exit 1
    fi
  elif [[ "$OS" == "Linux" ]]; then
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update -qq && sudo apt-get install -y jq
    elif command -v yum >/dev/null 2>&1; then
      sudo yum install -y jq
    else
      # fallback: download binary directly
      JQ_URL="https://github.com/jqlang/jq/releases/latest/download/jq-linux-amd64"
      curl -fsSL "$JQ_URL" -o /usr/local/bin/jq
      chmod +x /usr/local/bin/jq
    fi
  fi
  echo "  ✓ jq installed: $(jq --version)"
}

install_curl() {
  echo "  → Installing curl..."
  if [[ "$OS" == "Darwin" ]]; then
    brew install curl
  elif [[ "$OS" == "Linux" ]]; then
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update -qq && sudo apt-get install -y curl
    elif command -v yum >/dev/null 2>&1; then
      sudo yum install -y curl
    fi
  fi
  echo "  ✓ curl installed: $(curl --version | head -1)"
}

configure_aws_for_nebius() {
  echo ""
  echo "── Configuring AWS CLI for Nebius S3-compatible storage ──"

  # Load .env to get credentials
  load_env

  local key_id="${NEBIUS_AWS_ACCESS_KEY_ID:-}"
  local secret="${NEBIUS_AWS_SECRET_ACCESS_KEY:-}"

  if [[ -z "$key_id" || "$key_id" == "your_aws_access_key_id" ]]; then
    echo "  ⚠  NEBIUS_AWS_ACCESS_KEY_ID not set in .env"
    echo "     Get your key from: https://console.nebius.com → IAM → Service Accounts → Access Keys"
    echo "     Then set it in .env and re-run this script."
  else
    aws configure set aws_access_key_id "$key_id"
    aws configure set aws_secret_access_key "$secret"
    aws configure set region eu-north1
    aws configure set output json
    # Set the Nebius S3 endpoint as a named profile default
    aws configure set default.s3.endpoint_url https://storage.eu-north1.nebius.cloud
    echo "  ✓ AWS CLI configured for Nebius (region: eu-north1)"
    echo "  ✓ S3 endpoint: https://storage.eu-north1.nebius.cloud"
    echo "  ℹ  Note: always pass --endpoint-url https://storage.eu-north1.nebius.cloud"
    echo "           OR use: aws --profile nebius s3 ls"
  fi
}

# ──────────────────────────────────────────────
# Check + auto-install each dependency
# ──────────────────────────────────────────────

echo "── Checking prerequisites ─────────────────────────────"

# nebius CLI — cannot auto-install, must be done manually
if ! command -v nebius >/dev/null 2>&1; then
  echo "  ✗ nebius CLI not found."
  echo "    Install from: https://docs.nebius.com/cli"
  echo "    Then run: nebius auth login"
  exit 1
else
  echo "  ✓ nebius: $(nebius version)"
fi

# aws CLI
if ! command -v aws >/dev/null 2>&1; then
  echo "  ✗ aws not found — auto-installing..."
  install_aws
  configure_aws_for_nebius
else
  echo "  ✓ aws: $(aws --version 2>&1)"
  # Still check if it's configured for Nebius
  CURRENT_ENDPOINT="$(aws configure get default.s3.endpoint_url 2>/dev/null || true)"
  if [[ "$CURRENT_ENDPOINT" != *"nebius"* ]]; then
    echo "  ⚠  AWS CLI not yet configured for Nebius — configuring now..."
    configure_aws_for_nebius
  else
    echo "  ✓ AWS CLI already pointed at Nebius S3"
  fi
fi

# jq
if ! command -v jq >/dev/null 2>&1; then
  echo "  ✗ jq not found — auto-installing..."
  install_jq
else
  echo "  ✓ jq: $(jq --version)"
fi

# curl
if ! command -v curl >/dev/null 2>&1; then
  echo "  ✗ curl not found — auto-installing..."
  install_curl
else
  echo "  ✓ curl: $(curl --version | head -1)"
fi

# ──────────────────────────────────────────────
# Nebius project + subnet resolution
# ──────────────────────────────────────────────

load_env

echo ""
echo "── Resolving Nebius project ───────────────────────────"

if ! nebius config get parent-id >/dev/null 2>&1; then
  echo "  ✗ Nebius parent-id is not configured."
  echo "    Run: nebius profile create"
  echo "    Then: nebius config set parent-id <your_project_id>"
  exit 1
fi

PROJECT_ID="$(resolve_project_id)"
echo "  ✓ project_id: $PROJECT_ID"

echo ""
echo "── Resolving subnet ───────────────────────────────────"
SUBNET="$(resolve_subnet_id)"
echo "  ✓ subnet_id: $SUBNET"
echo "  ℹ  Tip: set NEBIUS_SUBNET_ID=$SUBNET in .env to pin it"

echo ""
echo "── All prereqs satisfied ✓ ────────────────────────────"