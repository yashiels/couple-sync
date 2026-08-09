# App releases (Android + iOS)

The backend ships as a Docker image (see `deploy.md`). This doc covers the **client** release
workflows:

- `.github/workflows/android-release.yml` — signed `.apk` on `ubuntu-latest`, attached to the GitHub Release.
- `.github/workflows/ios-release.yml` — signed `.ipa` on `macos-26`, uploaded to **TestFlight** (paid
  Apple team; push entitlement kept). macos-26 is required: expo-modules-jsi (SDK 57) only compiles on
  Xcode ≥26.4 (Swift 6.2); older images fail.

Both trigger on a `v*` tag push (or manual `workflow_dispatch`) and read their secrets from 1Password
using a single GitHub repo secret, `OP_SERVICE_ACCOUNT_TOKEN`. The Android workflow also still accepts
plain GitHub repo secrets as a fallback when that token is not set.

> **Status:** fully provisioned and shipped once (`v0.1.0`). The credentials below already exist in
> 1Password — this doc is the reference for what's wired and how to re-provision (e.g. when the iOS
> Distribution cert or profile expires, ~1 year). iOS signing is **manual** (a managed Apple
> Distribution cert + App Store profile); automatic/cloud signing did not work on GitHub runners.

---

## a) Apple portal actions (one-time, done by you in a browser)

1. **App Store Connect API key** (done) — App Store Connect → Users and Access → Integrations → App
   Store Connect API → **Team Keys** → key with role **App Manager**. The `.p8` downloads once. Used by
   the workflow only to **upload** to TestFlight (`altool`) — NOT for signing (see step 5). Note the
   **Key ID** + **Issuer ID**.
2. **App ID** — Certificates, Identifiers & Profiles → Identifiers: App ID `dev.yashiel.couplesync`
   with **Push Notifications** enabled.
3. **App record in App Store Connect** (done) — Apps → **+** → New App, iOS, bundle id
   `dev.yashiel.couplesync`. TestFlight uploads land here. Add testers under the app's **TestFlight**
   tab (Internal = your team, installs immediately; External = up to 10k, one-time beta review); they
   install via the **TestFlight** iOS app.
4. **Team ID** — Apple Developer → Membership (10 chars: `3ZD88GJ8SJ`).
5. **iOS Distribution cert + App Store profile** (done — MANUAL signing) — created with
   `fastlane cert` (an Apple Distribution cert, id `85V8539546`) + `fastlane sigh --app_identifier
   dev.yashiel.couplesync` (App Store profile `dev.yashiel.couplesync AppStore`), using the ASC API key.
   Both are stored in 1Password (see below) and imported into a throwaway keychain at build time by the
   workflow's "Set up code signing" step; `plugins/withIosManualSigning.js` applies them to only the app
   target. **Re-provision the same way** when the cert/profile expire (~1 year) and re-store the base64.
6. **APNs auth key for Firebase push** — App Store Connect API keys do **not** carry push. Create a
   separate **APNs Auth Key** (Certificates, Identifiers & Profiles → Keys → new key, check **Apple
   Push Notifications service (APNs)**), download its `.p8`, and upload it in the **Firebase console →
   Project settings → Cloud Messaging → Apple app configuration**. Without this, FCM push to iOS fails
   even though the build is signed. (Export-compliance is auto-answered via
   `ios.infoPlist.ITSAppUsesNonExemptEncryption=false` — HTTPS/TLS only.)

## b) New 1Password fields (vault **Nexion**, item **couple-sync**)

Secrets are split by scope. **Account-wide Apple creds** (identical for every iOS app on this Apple
account) live in the shared **`Agents`** vault, item **`apple-developer`**. **App-specific** creds
live in **`Nexion`**, item **`couple-sync`**. Field names are the exact `op://` references the
workflows read.

**`op://Agents/apple-developer/…` (account-wide — reused by all iOS apps):**

| Field name | Value |
|---|---|
| `asc_api_key_id` | App Store Connect API **Key ID** (upload). |
| `asc_issuer_id` | The **Issuer ID**. |
| `asc_api_key_p8_base64` | The ASC `.p8`, base64 (see below). |
| `apple_team_id` | Team ID (`3ZD88GJ8SJ`). |
| `ios_dist_cert_p12_base64` | Apple **Distribution** cert `.p12`, base64 (manual signing). |
| `ios_dist_cert_password` | Export password for that `.p12`. |

**`op://Nexion/couple-sync/…` (this app only):**

| Field name | Value |
|---|---|
| `google_services_info_plist_b64` | base64 of iOS `GoogleService-Info.plist`. |
| `google_web_client_id` | Web OAuth client id (Google sign-in). |
| `ios_appstore_profile_base64` | base64 of the App Store `.mobileprovision`. |
| `ios_appstore_profile_name` | The profile Name (`dev.yashiel.couplesync AppStore`) — used in ExportOptions. |
| `keystore_base64` / `keystore_password` / `key_alias` / `key_password` / `google_services_json_b64` | Android release signing + Firebase (used by `android-release.yml`). |

Base64-encode the `.p8` (one line, no wrapping):

```bash
# macOS
base64 -i AuthKey_XXXXXXXXXX.p8 | tr -d '\n' | pbcopy
# Linux
base64 -w0 AuthKey_XXXXXXXXXX.p8
```

The iOS workflow decodes it back to `AuthKey_<asc_api_key_id>.p8` at build time.

## c) The single GitHub repo secret: `OP_SERVICE_ACCOUNT_TOKEN`

1. In 1Password, open **Settings → Developer → Service Accounts → New Service Account** (or
   `op service-account create`).
2. Name it (e.g. `couple-sync-ci`) and grant it **read-only** access to **both** the **`Agents`** vault
   (account-wide Apple creds) and the **`Nexion`** vault (this app's Firebase + Android keystore).
   Grant no other vaults.
3. Copy the generated token (shown once).
4. In GitHub: **repo → Settings → Secrets and variables → Actions → New repository secret**, name it
   **`OP_SERVICE_ACCOUNT_TOKEN`**, paste the token.

That is the only GitHub secret required for the iOS build, and the only one needed to switch the
Android build onto the 1Password path. (Without it, the Android build falls back to the individual
`ANDROID_*` / `GOOGLE_*` GitHub secrets and still works.)

## d) Cut a release

```bash
# from a clean main that is green in CI
git tag v1.0.0
git push origin v1.0.0
```

The tag push fires both release workflows:
- **Android** (`android-release`) builds a **signed APK**, uploads it as a workflow artifact, and
  attaches it to the **GitHub Release** for that tag. Testers download the APK and sideload it
  (enable "install unknown apps").
- **iOS** (`ios-release` → "Deploy: iOS TestFlight") builds a signed IPA and **uploads it to
  TestFlight**. It appears in the app's TestFlight tab after Apple finishes processing (a few
  minutes); testers install via the TestFlight app. There is no iOS GitHub Release — a raw `.ipa`
  cannot be sideloaded. The build number is the workflow run number, so re-runs never collide.

To rehearse without tagging, run either workflow from the Actions tab via **Run workflow** (both also
upload their installable as a downloadable artifact).
