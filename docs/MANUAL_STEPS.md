# Manual Setup Steps for Couple Sync

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

## VPS self-host setup

The self-hosted backend (Fastify + Postgres + WS, replacing Firestore/Cloud Functions) runs on the Oracle Always Free ARM VPS. These steps are manual console / DNS / firewall work — they cannot be automated by `deploy.sh`.

### 1. Firebase Spark service account (free, no Blaze)
The backend keeps Firebase Auth + FCM (both free on Spark). It needs a service-account key to call `admin.auth().verifyIdToken` and `admin.messaging().sendEachForMulticast` from the VPS.

1. Firebase Console → pick your Spark project → **Project Settings → Service Accounts**.
2. Click **"Generate new private key"** → download the JSON file.
3. Stringify the JSON (e.g. `jq -c . < downloaded-key.json`) and paste the full single-line result into `backend/.env` as `FIREBASE_SERVICE_ACCOUNT_JSON`.
4. Set `FIREBASE_PROJECT_ID` in the same `.env` to the project ID shown at the top of Project Settings.
5. Confirm Auth providers (Email/Google/Apple) and FCM are enabled — they are by default on Spark.

### 2. Point the API domain at the VPS IP
1. In your DNS provider, create an **A record** for your chosen api subdomain (e.g. `api.yourdomain.tld`) pointing at the VPS public IP.
2. Wait for propagation (`dig +short api.yourdomain.tld` should return the VPS IP).
3. Set `DOMAIN=api.yourdomain.tld` in `backend/.env` on the VPS — Caddy reads this and auto-provisions TLS.

### 3. Open ports 80/443 on the Oracle VPS
Oracle Cloud's default VCN security list blocks inbound HTTP/HTTPS. Two layers must be opened:

**a. VCN Security List (Oracle Cloud Console)**
1. Oracle Cloud Console → Networking → Virtual Cloud Networks → pick your VCN → Security Lists → Default Security List (or the one attached to your instance's subnet).
2. Add **Ingress** rules:
   - `0.0.0.0/0` TCP **80** (HTTP, Caddy HTTP-01 challenge + redirect)
   - `0.0.0.0/0` TCP **443** (HTTPS)
3. Save.

**b. iptables on the VPS itself**
Oracle's Ubuntu/Oracle-Linux images ship with iptables rules that drop everything except SSH even after the security list is opened. On the VPS:

```bash
sudo iptables -I INPUT 6 -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT 6 -p tcp --dport 443 -j ACCEPT
sudo netfilter-persistent save   # Ubuntu/Debian
# or: sudo /sbin/iptables-save | sudo tee /etc/iptables/rules.v4
```

Verify from outside the VPS: `curl -sI http://api.yourdomain.tld/health` should reach Caddy (a redirect or 200, not a timeout).

### 4. Bootstrap + deploy
1. First-time only — on the VPS:
   ```bash
   sudo mkdir -p /opt/couple-sync && sudo chown -R $USER /opt/couple-sync
   git clone <your-repo-url> /opt/couple-sync
   cd /opt/couple-sync
   cp backend/.env.example backend/.env
   # edit backend/.env: DATABASE_URL is overridden by compose; set FIREBASE_PROJECT_ID,
   # FIREBASE_SERVICE_ACCOUNT_JSON, DOMAIN. ADMIN_TOKEN optional.
   ```
2. From your laptop:
   ```bash
   VPS_HOST=user@your-vps-host ./deploy.sh
   ```
   The script pulls, rebuilds the stack, waits for postgres, and runs migrations. Re-runnable.

### 5. Point the Flutter app at the API
Set the backend `baseUrl` in the Flutter app config (see `lib/services/sync_service.dart`) to `https://api.yourdomain.tld`. The WS URL is `wss://api.yourdomain.tld/sync`.

### 6. Postgres backups (optional, ~$0)
Set a cron on the VPS for nightly `pg_dump` to a B2/S3 bucket:

```bash
0 3 * * *  docker compose -f /opt/couple-sync/docker-compose.yml exec -T postgres pg_dump -U couple couplesync | gzip > /backups/couplesync-$(date +\%F).sql.gz
```


