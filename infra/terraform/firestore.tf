# -----------------------------------------------------------------------------
# firestore.tf – Firestore database configuration
# -----------------------------------------------------------------------------
# location_id is permanent and cannot be changed after creation, so we protect
# this resource with prevent_destroy. The "nam5" location is the US
# multi-region (United States), providing high availability and durability.
# -----------------------------------------------------------------------------

resource "google_firestore_database" "default" {
  provider    = google-beta
  project     = var.project_id
  name        = "(default)"
  location_id = "nam5"
  type        = "FIRESTORE_NATIVE"

  # The database location cannot be changed after creation.
  # prevent_destroy guards against accidental deletion.
  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.firestore]
}
