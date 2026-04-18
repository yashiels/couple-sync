# -----------------------------------------------------------------------------
# prod.tfvars – Production environment variable values
# -----------------------------------------------------------------------------
# Usage: terraform plan -var-file=environments/prod.tfvars
# -----------------------------------------------------------------------------

project_id = "nexion-ai-prod"
region     = "us-central1"

# TODO: Replace with your actual billing account ID (format: XXXXXX-XXXXXX-XXXXXX)
# Find it via: gcloud billing accounts list
# billing_account = "XXXXXX-XXXXXX-XXXXXX"

# TODO: Replace with the project owner's email for budget alerts
# owner_email = "owner@example.com"
