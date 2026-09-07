# 1Password-injectable template for the couple-sync Atlas runtime env (~/apps/couple-sync/.env).
# Rendered ONCE on Atlas, never committed/rsynced:  op inject -i atlas.env.tpl -o .env && chmod 600 .env
# Source: the single "couple-sync" item in the Nexion vault (referenced by UUID) — the same item the
# app and local dev use. Nothing here is a secret value; the refs are useless without vault access.

POSTGRES_PASSWORD="op://Nexion/rn47nl5ayzg2cztuw4tmizbrvi/postgres_password"
FIREBASE_PROJECT_ID="op://Nexion/rn47nl5ayzg2cztuw4tmizbrvi/firebase_project_id"
FIREBASE_SERVICE_ACCOUNT_JSON="op://Nexion/rn47nl5ayzg2cztuw4tmizbrvi/firebase_service_account_json"

# Not a secret (mobile app sends no cookies; single origin just satisfies config.ts, which refuses '*').
CORS_ORIGINS="https://couple-sync.yashiel.dev"

# Optional — admin routes 503 until set.
ADMIN_TOKEN="op://Nexion/rn47nl5ayzg2cztuw4tmizbrvi/admin_token"

# Cloudflare tunnel "atlas-couple-sync" (couple-sync.yashiel.dev -> http://api:3000).
TUNNEL_TOKEN="op://Nexion/rn47nl5ayzg2cztuw4tmizbrvi/tunnel_token"
