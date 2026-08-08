# 1Password-injectable template for the Fastify backend env (backend/.env), for LOCAL dev.
# Resolve with:  op inject -i backend/.env.tpl -o backend/.env
#
# Secrets are 1Password references, useless without the Nexion vault. They point at the single
# "couple-sync" item (referenced by UUID) — the one source of truth for all couple-sync secrets,
# also used by the Atlas deploy. Nothing here is a secret value.
#
# In production (Atlas) these come from ~/apps/couple-sync/.env, not this file.

# Local dev default — the docker-compose.override.yml Postgres uses trust auth. In prod, Atlas's
# compose builds DATABASE_URL from POSTGRES_PASSWORD itself.
DATABASE_URL="postgres://postgres@localhost:5432/couple_sync"

FIREBASE_PROJECT_ID="op://Nexion/rn47nl5ayzg2cztuw4tmizbrvi/firebase_project_id"
FIREBASE_SERVICE_ACCOUNT_JSON="op://Nexion/rn47nl5ayzg2cztuw4tmizbrvi/firebase_service_account_json"

# Not a secret (mobile app sends no cookies; single origin just satisfies config.ts).
CORS_ORIGINS="https://couple-sync.yashiel.dev"

# Optional — admin routes 503 until set.
ADMIN_TOKEN="op://Nexion/rn47nl5ayzg2cztuw4tmizbrvi/admin_token"

# Optional — defaults to 3000.
# PORT="3000"
