# -----------------------------------------------------------------------------
# apis.tf – Enable required GCP APIs for the project
# -----------------------------------------------------------------------------
# disable_on_destroy = false ensures APIs stay enabled even if the Terraform
# resource is removed, preventing accidental service disruption.
# -----------------------------------------------------------------------------

resource "google_project_service" "firestore" {
  provider = google-beta
  project  = var.project_id
  service  = "firestore.googleapis.com"

  disable_on_destroy = false
}

resource "google_project_service" "cloudfunctions" {
  provider = google-beta
  project  = var.project_id
  service  = "cloudfunctions.googleapis.com"

  disable_on_destroy = false
}

resource "google_project_service" "cloudbuild" {
  provider = google-beta
  project  = var.project_id
  service  = "cloudbuild.googleapis.com"

  disable_on_destroy = false
}

resource "google_project_service" "artifactregistry" {
  provider = google-beta
  project  = var.project_id
  service  = "artifactregistry.googleapis.com"

  disable_on_destroy = false
}

resource "google_project_service" "eventarc" {
  provider = google-beta
  project  = var.project_id
  service  = "eventarc.googleapis.com"

  disable_on_destroy = false
}

resource "google_project_service" "run" {
  provider = google-beta
  project  = var.project_id
  service  = "run.googleapis.com"

  disable_on_destroy = false
}

# Google Calendar API – used for calendar integration features
resource "google_project_service" "calendar" {
  provider = google-beta
  project  = var.project_id
  service  = "calendar-json.googleapis.com"

  disable_on_destroy = false
}

# Google People API – used for contacts / partner-linking features
resource "google_project_service" "people" {
  provider = google-beta
  project  = var.project_id
  service  = "people.googleapis.com"

  disable_on_destroy = false
}
