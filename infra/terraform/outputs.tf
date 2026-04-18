# -----------------------------------------------------------------------------
# outputs.tf – Expose Firebase config files for CI/CD or local use
# -----------------------------------------------------------------------------
# These outputs contain the contents of google-services.json and
# GoogleService-Info.plist. They are marked sensitive because they include
# API keys and app identifiers.
# -----------------------------------------------------------------------------

output "google_services_json" {
  description = "Content of google-services.json for the Android app"
  value       = data.google_firebase_android_app_config.couple_sync.config_file_contents
  sensitive   = true
}

output "google_service_info_plist" {
  description = "Content of GoogleService-Info.plist for the iOS app"
  value       = data.google_firebase_apple_app_config.couple_sync.config_file_contents
  sensitive   = true
}
