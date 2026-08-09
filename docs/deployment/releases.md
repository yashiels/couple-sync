# App releases (Android + iOS)

The backend ships as a Docker image (see `deploy.md`). This doc covers the **client** release
workflows that build signed installables and attach them to a GitHub Release:

- `.github/workflows/android-release.yml` — signed `.apk` on `ubuntu-latest`.
- `.github/workflows/ios-release.yml` — signed `.ipa` on `macos-14` (paid Apple team; push entitlement kept).

Both trigger on a `v*` tag push (or manual `workflow_dispatch`) and both read their secrets from
1Password using a single GitHub repo secret, `OP_SERVICE_ACCOUNT_TOKEN`. The Android workflow also
still accepts plain GitHub repo secrets as a fallback when that token is not set.

---

## a) Apple portal actions (one-time, done by you in a browser)

1. **App Store Connect API key** — App Store Connect → Users and Access → Integrations → App Store
   Connect API → **Team Keys** → generate a key with role **App Manager** (or **Admin**). Download the
   `.p8` **once** (it cannot be re-downloaded). Note the **Key ID** and the **Issuer ID** shown on that
   page. This key is what lets `xcodebuild` sign and (optionally) upload without an Apple ID password.
2. **App ID / bundle identifier** — in the Apple Developer portal (Certificates, Identifiers &
   Profiles → Identifiers), confirm an App ID exists for **`dev.yashiel.couplesync`** with the
   **Push Notifications** capability enabled. Automatic signing will create the provisioning profile,
   but the identifier itself must exist first.
2b. **App record in App Store Connect** — App Store Connect → **Apps → +** → **New App**, platform iOS,
   bundle id `dev.yashiel.couplesync`, pick a name + SKU. TestFlight uploads have nowhere to land
   without this record. After the first successful upload, add testers under the app's **TestFlight**
   tab (Internal Testing group = your team, installs immediately; External = up to 10k, one-time beta
   review). Testers install builds through the **TestFlight** iOS app.
3. **Team ID** — Apple Developer → Membership. Copy the 10-character Team ID (e.g. `A1B2C3D4E5`); the
   iOS workflow needs it so automatic signing can pick the right team.
4. **APNs auth key for Firebase push** — App Store Connect API keys do **not** carry push. Create a
   separate **APNs Auth Key** (Certificates, Identifiers & Profiles → Keys → new key, check **Apple
   Push Notifications service (APNs)**), download its `.p8`, and upload it in the **Firebase console →
   Project settings → Cloud Messaging → Apple app configuration**, entering the APNs Key ID and your
   Team ID. Without this, FCM push to iOS silently fails even though the build is signed correctly.

## b) New 1Password fields (vault **Nexion**, item **couple-sync**)

Secrets are split by scope. **Account-wide Apple creds** (identical for every iOS app on this Apple
account) live in the shared **`Agents`** vault, item **`apple-developer`**. **App-specific** creds
live in **`Nexion`**, item **`couple-sync`**. Field names are the exact `op://` references the
workflows read.

**`op://Agents/apple-developer/…` (account-wide — reused by all iOS apps):**

| Field name | Value |
|---|---|
| `asc_api_key_id` | The App Store Connect API **Key ID** from step (a1). |
| `asc_issuer_id` | The **Issuer ID** from step (a1). |
| `asc_api_key_p8_base64` | The `.p8` file, base64-encoded (see below). |
| `apple_team_id` | The 10-char **Team ID** from step (a3). |

**`op://Nexion/couple-sync/…` (this app only):**

| Field name | Value |
|---|---|
| `google_services_info_plist_b64` | base64 of iOS `GoogleService-Info.plist`. |
| `google_web_client_id` | Web OAuth client id (Google sign-in). |
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
