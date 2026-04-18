#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== Couple Sync Infrastructure Setup ==="
echo ""

# -------------------------------------------------------
# 1. Check prerequisites
# -------------------------------------------------------
echo "Checking prerequisites..."

if ! command -v gcloud &>/dev/null; then
  echo "ERROR: gcloud CLI is not installed."
  echo "Install it from https://cloud.google.com/sdk/docs/install"
  exit 1
fi
echo "  gcloud  ... OK"

if ! command -v terraform &>/dev/null; then
  echo "ERROR: terraform is not installed."
  echo "Install it from https://developer.hashicorp.com/terraform/downloads"
  exit 1
fi
echo "  terraform ... OK"

if ! command -v firebase &>/dev/null; then
  echo "ERROR: Firebase CLI is not installed."
  echo "Install it with: npm install -g firebase-tools"
  exit 1
fi
echo "  firebase ... OK"

echo ""
echo "All prerequisites satisfied."
echo ""

# -------------------------------------------------------
# 2. Run Terraform
# -------------------------------------------------------
echo "Initializing and applying Terraform configuration..."
cd "$PROJECT_ROOT/infra/terraform"

terraform init
terraform apply -var-file=environments/prod.tfvars

echo ""
echo "Terraform apply complete."
echo ""

# -------------------------------------------------------
# 3. Remind about manual steps
# -------------------------------------------------------
echo "=== MANUAL STEPS REMAINING ==="
echo ""
echo "Please review infra/README.md for any manual configuration steps, including:"
echo "  - Enabling Firebase Authentication providers (Google, Apple)"
echo "  - Configuring OAuth consent screen in GCP Console"
echo "  - Adding SHA-1 fingerprint for Android"
echo "  - Setting up Apple Services ID for Sign in with Apple"
echo ""
echo "You can also run ./infra/scripts/enable-auth.sh for a step-by-step guide."
echo ""
echo "=== Setup complete ==="
