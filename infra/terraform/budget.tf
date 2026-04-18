# -----------------------------------------------------------------------------
# budget.tf – Billing budget alert for the Blaze-plan project
# -----------------------------------------------------------------------------
# On the Blaze (pay-as-you-go) plan, costs can exceed the free tier.  This
# budget sends email notifications to the project owner at 50% and 100% of
# a $1/month threshold so unexpected charges are caught quickly.
#
# NOTE: The service account running Terraform needs the
# "Billing Account Costs Manager" role on the billing account, or use the
# google_billing_account_iam_member resource below to grant it.
# -----------------------------------------------------------------------------

# Retrieve billing account details for the budget filter
data "google_billing_account" "account" {
  provider        = google-beta
  billing_account = var.billing_account
}

# Grant the project's default service account access to manage budgets.
# This may already be granted at the org level; if so, this is a no-op.
resource "google_billing_account_iam_member" "budget_viewer" {
  provider           = google-beta
  billing_account_id = var.billing_account
  role               = "roles/billing.costsManager"
  member             = "user:${var.owner_email}"
}

resource "google_billing_budget" "monthly" {
  provider        = google-beta
  billing_account = var.billing_account
  display_name    = "CoupleSync Monthly Budget"

  budget_filter {
    projects = ["projects/${var.project_id}"]
  }

  # $1.00 USD per month
  amount {
    specified_amount {
      currency_code = "USD"
      units         = "1"
    }
  }

  # Alert at 50% of budget ($0.50)
  threshold_rules {
    threshold_percent = 0.5
    spend_basis       = "CURRENT_SPEND"
  }

  # Alert at 100% of budget ($1.00)
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "CURRENT_SPEND"
  }

  # Send alerts to the project owner via email
  all_updates_rule {
    monitoring_notification_channels = []
    disable_default_iam_recipients   = false

    # Schema note: email notifications go to Billing Account Admins and
    # the users listed in monitoring_notification_channels by default.
    # We keep disable_default_iam_recipients = false so the owner_email
    # (granted costsManager above) receives alerts automatically.
  }
}
