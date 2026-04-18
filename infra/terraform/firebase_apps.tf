# -----------------------------------------------------------------------------
# firebase_apps.tf – Firebase Android and iOS app registrations
# -----------------------------------------------------------------------------
# These resources register the mobile apps with the Firebase project so that
# google-services.json (Android) and GoogleService-Info.plist (iOS) configs
# can be generated and consumed by the Flutter build.
# -----------------------------------------------------------------------------

resource "google_firebase_android_app" "couple_sync" {
  provider     = google-beta
  project      = var.project_id
  display_name = "CoupleSync Android"
  package_name = "com.skyner.coupleSync"

  depends_on = [google_project_service.firestore]
}

resource "google_firebase_apple_app" "couple_sync" {
  provider     = google-beta
  project      = var.project_id
  display_name = "CoupleSync iOS"
  bundle_id    = "com.skyner.coupleSync"

  depends_on = [google_project_service.firestore]
}

# -----------------------------------------------------------------------------
# Data sources to retrieve generated config files for each platform
# -----------------------------------------------------------------------------

data "google_firebase_android_app_config" "couple_sync" {
  provider = google-beta
  project  = var.project_id
  app_id   = google_firebase_android_app.couple_sync.app_id
}

data "google_firebase_apple_app_config" "couple_sync" {
  provider = google-beta
  project  = var.project_id
  app_id   = google_firebase_apple_app.couple_sync.app_id
}
