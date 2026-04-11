# -----------------------------------------------------------------------------
# variables.tf – Input variables for the CoupleSync Terraform configuration
# -----------------------------------------------------------------------------

variable "project_id" {
  description = "The GCP project ID (e.g. nexion-ai-prod)"
  type        = string
}

variable "region" {
  description = "Default GCP region for regional resources"
  type        = string
  default     = "us-central1"
}

variable "billing_account" {
  description = "The GCP billing account ID (format: XXXXXX-XXXXXX-XXXXXX)"
  type        = string
}

variable "owner_email" {
  description = "Email address of the project owner for budget alert notifications"
  type        = string
}
