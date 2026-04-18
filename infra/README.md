# Infrastructure Setup

Terraform + Firebase CLI infrastructure for **Couple Schedule** (`nexion-ai-prod`). Provisions GCP APIs, Firebase apps, Firestore, and a billing budget alert, then deploys Cloud Functions and security rules.

## Prerequisites

| Tool | Install |
|------|---------|
| gcloud CLI | [cloud.google.com/sdk/docs/install](https://cloud.google.com/sdk/docs/install) |
| Terraform >= 1.5 | [developer.hashicorp.com/terraform/downloads](https://developer.hashicorp.com/terraform/downloads) |
| Firebase CLI | `npm install -g firebase-tools` |
| FlutterFire CLI | `dart pub global activate flutterfire_cli` |

You also need a Google Cloud project on the **Blaze plan** with billing enabled.

## Quick Start

```bash
# 1. Create a local tfvars file from the template
cd infra/terraform
cp environments/prod.tfvars environments/local.tfvars

# 2. Edit local.tfvars — fill in billing_account and owner_email
#    billing_account = "XXXXXX-XXXXXX-XXXXXX"  (from: gcloud billing accounts list)
#    owner_email     = "you@example.com"

# 3. Authenticate with GCP
gcloud auth application-default login

# 4. Provision infrastructure (runs terraform init + apply)
cd ..
./scripts/setup.sh

# 5. Generate Firebase config files for Flutter
./scripts/configure-flutter.sh

# 6. Print manual auth setup guide
./scripts/enable-auth.sh

# 7. Deploy Cloud Functions + Firestore rules
./scripts/deploy-all.sh
```

## Manual Steps

Terraform cannot automate the following. See [`docs/MANUAL_STEPS.md`](../docs/MANUAL_STEPS.md) for detailed instructions.

- **OAuth consent screen** -- Configure as External type, add test users in GCP Console
- **Google Sign-In** -- Enable the Google provider in Firebase Console > Authentication > Sign-in method
- **Apple Sign-In** -- Enable the Apple provider in Firebase Console; requires a paid Apple Developer account
- **Android SHA-1 fingerprint** -- Run `cd android && ./gradlew signingReport`, then add the SHA-1 in Firebase Console > Project Settings > Android app
- **Apple Services ID** -- Create a Services ID in the Apple Developer portal and configure the return URL (`https://nexion-ai-prod.firebaseapp.com/__/auth/handler`)

## Scripts Reference

All scripts live in `infra/scripts/` and should be run from the `infra/` directory.

| Script | Description |
|--------|-------------|
| `setup.sh` | Checks prerequisites, runs `terraform init` + `terraform apply` |
| `configure-flutter.sh` | Installs FlutterFire CLI if missing, runs `flutterfire configure` to generate Firebase config files |
| `enable-auth.sh` | Prints a step-by-step guide for manually enabling Google and Apple auth providers |
| `deploy-all.sh` | Runs `deploy-functions.sh` then `deploy-rules.sh` |
| `deploy-functions.sh` | Installs dependencies, builds, lints, tests, and deploys Cloud Functions |
| `deploy-rules.sh` | Deploys Firestore security rules and indexes |

## Terraform Resources

The Terraform configuration in `infra/terraform/` provisions:

| Resource | Details |
|----------|---------|
| 8 GCP APIs | Firestore, Cloud Functions, Cloud Build, Artifact Registry, Eventarc, Cloud Run, Calendar API, People API |
| Firebase Android app | `com.skyner.coupleSync` |
| Firebase iOS app | `com.skyner.coupleSync` |
| Firestore database | `(default)`, location `nam5` (US multi-region), `FIRESTORE_NATIVE` mode |
| Billing budget | $1/month with alerts at 50% and 100% thresholds |

## Important Notes

- **Firestore location (`nam5`) is permanent** and cannot be changed after database creation.
- **Never commit `*.tfstate` files or API keys** to git. These are excluded via `.gitignore`.
- **Budget alert requires billing account admin access.** The Terraform service account (or your user) needs the `Billing Account Costs Manager` role.
