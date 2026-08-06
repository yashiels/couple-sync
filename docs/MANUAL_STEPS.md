# Manual Setup Steps for Couple Sync

> **Superseded by the Setup section of `README.md`.** Retained for history only — the Blaze plan,
> Cloud Functions and Firestore steps below no longer apply. Firebase is used for Auth and FCM only.

This document tracks setup steps that require manual console access.

## STORY-001: Firebase Cost Alerts

### Blaze Plan Verification
The project `nexion-ai-prod` must be on the Blaze plan for Cloud Functions.

**Verification Steps:**
1. Go to [Firebase Console](https://console.firebase.google.com/project/nexion-ai-prod/usage/details)
2. Navigate to Usage and Billing
3. Confirm Blaze plan is active

### Cost Alert Configuration ($1/month threshold)

**Steps:**
1. Go to [GCP Billing Budgets](https://console.cloud.google.com/billing/0157F6-3F3CDD-C7B9A2/budgets?project=nexion-ai-prod)
2. Click "Create Budget"
3. Configure:
   - Name: `couple-sync-monthly-limit`
   - Amount: $1.00
   - Scope: Project `nexion-ai-prod`
   - Alerts: 50%, 90%, 100% thresholds
   - Email notifications: Enable for project owners
4. Save

### Free Tier Guidelines
- Cloud Functions: Stay under 2M invocations/month
- Firestore: Stay under 50K reads/day, 20K writes/day
- Storage: Minimal usage expected
- FCM: Free tier covers all notification needs

## Future Manual Steps

(Add additional manual setup requirements here as they are discovered)

## STORY-002: Flutter Project Setup

### Apple Sign-In Configuration (iOS)

Apple Sign-In requires an Apple Developer account and proper capability configuration.

**Steps:**
1. Ensure you have an active Apple Developer account ($99/year)
2. Open `ios/Runner.xcworkspace` in Xcode
3. Select the Runner project
4. Go to Signing & Capabilities tab
5. Click "+ Capability" and add "Sign in with Apple"
6. Ensure the bundle ID matches your Apple Developer App ID
7. Configure the capability in Apple Developer Console:
   - Go to [Apple Developer Console](https://developer.apple.com/account)
   - Navigate to Certificates, Identifiers & Profiles
   - Find your App ID and enable "Sign in with Apple"
   - Create necessary provisioning profiles

### iOS Build Verification

The first iOS build should be verified manually:

```bash
cd /Volumes/pulsar/apex-local/Developer/github/skyner-group/couple-sync
~/flutter/bin/flutter build ios --no-codesign
```

**Note:** Build may take 5-10 minutes on first run due to CocoaPods installation.

### Android Build Verification

Android debug build should be verified:

```bash
cd /Volumes/pulsar/apex-local/Developer/github/skyner-group/couple-sync
~/flutter/bin/flutter build apk --debug
```

**Note:** Build may take 3-5 minutes on first run due to Gradle setup.

### Platform-Specific Notes

- **iOS**: Requires macOS with Xcode installed
- **Android**: Requires Android SDK (included with Flutter)
- **Apple Sign-In**: Only works on physical iOS devices, not simulators
- **Google Sign-In**: Requires OAuth 2.0 client ID configuration in Google Cloud Console

## Google Calendar API

1. GCP Console → APIs & Services → enable **Google Calendar API** for the Firebase project.
2. The OAuth consent screen must include the `https://www.googleapis.com/auth/calendar.readonly` scope.
3. freebusy costs 1 quota unit/call; the default per-user quota is 1M/day — far above our ≤1/hour throttle.

## App Check (one-time console setup)
1. Firebase Console → App Check → register iOS (DeviceCheck) and Android (Play Integrity).
2. Enforce App Check on **Cloud Firestore** (writes) and **Cloud Functions** (callables).
3. Copy the debug secret; add to `firebase.json` `appCheck` debug token for local dev, or set via the debug provider in `lib/main.dart`.

## Self-host backend setup (managed Docker platform / Coolify)

The self-hosted backend (Fastify + Postgres + WS, replacing Firestore/Cloud Functions) deploys as a managed Docker app behind the platform's reverse proxy (Traefik on Coolify). **No Caddy, no host port binding** — the container only `expose`s 3000 and the platform proxy terminates TLS. These steps are manual console/DNS work — they cannot be automated.

### 1. Firebase Spark service account (free, no Blaze)
The backend keeps Firebase Auth + FCM (both free on Spark). It needs a service-account key to call `admin.auth().verifyIdToken` and `admin.messaging().sendEachForMulticast`.

1. Firebase Console → pick your Spark project → **Project Settings → Service Accounts**.
2. Click **"Generate new private key"** → download the JSON file.
3. Stringify the JSON (e.g. `jq -c . < downloaded-key.json`) → paste the full single-line result into the platform's Environment panel as `FIREBASE_SERVICE_ACCOUNT_JSON` (locally: `backend/.env`).
4. Set `FIREBASE_PROJECT_ID` to the project ID shown at the top of Project Settings.
5. Confirm Auth providers (Email/Google/Apple) and FCM are enabled — they are by default on Spark.

### 2. Provision Postgres on the platform
On Coolify: **New Resource → Postgres** (managed). Copy the generated connection string — you'll set it as `DATABASE_URL` on the api service. (For a self-managed VPS, run `postgres:16` in the compose override and use that connection string.)

### 3. Create the app + set runtime env
On Coolify: **New Resource → Git** → pick this repo + branch; build pack = `docker-compose.yml` (or the `backend/Dockerfile`). In the service's **Environment** panel set:
- `DATABASE_URL` — the managed Postgres connection string (NOT hardcoded `couple/couple`).
- `FIREBASE_PROJECT_ID`, `FIREBASE_SERVICE_ACCOUNT_JSON`.
- `ADMIN_TOKEN` (optional).

**No committed `.env` in prod** — the platform injects these at runtime.

### 4. Add the domain (platform issues TLS)
In Coolify: **Settings → Domains** → add `api.yourdomain.tld`. Point its DNS A record at the Coolify server IP. The platform proxy (Traefik) issues the Let's Encrypt cert automatically and routes to the container's port 3000 (the `traefik.http.services.api.loadbalancer.server.port=3000` label in `docker-compose.yml` tells it which port). **Do not bind host 80/443** — the platform already owns those.

### 5. Deploy + verify
Push to the branch (`./deploy.sh` or `git push`) → Coolify builds + rolls the container. Migrations run automatically on start (the image CMD runs `node dist/migrate.js` before `node dist/index.js`). For a one-off migration: `docker compose exec api node dist/migrate.js`.

Verify: `curl https://api.yourdomain.tld/health` → `{"status":"ok"}`.

### 6. Point the Flutter app at the API
Build with `--dart-define` (or `--dart-define-from-file=env/prod.json`):
```bash
flutter build apk \
  --dart-define=API_BASE_URL=https://api.yourdomain.tld \
  --dart-define=WS_URL=wss://api.yourdomain.tld/sync
```
See `lib/env/app_env.dart` + `env/dev.json`/`env/prod.json`.

### 7. Postgres backups (optional, ~$0)
Nightly `pg_dump` from the managed Postgres to a B2/S3 bucket (Coolify has a built-in backup for managed Postgres, or run a cron sidecar).


