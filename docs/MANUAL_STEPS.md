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
