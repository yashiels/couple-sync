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
