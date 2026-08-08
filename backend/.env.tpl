# 1Password-injectable template for the Fastify backend env (backend/.env).
# Values are references, not secrets — useless without access to the "Nexion" vault.
# Resolve with:  op inject -i backend/.env.tpl -o backend/.env
# Vault item:    "couple-sync-env" in the Nexion vault (fields are the env-var names)
#
# The real service-account JSON and Postgres URL live only in 1Password / the deploy
# platform's env panel — never committed. FIREBASE_SERVICE_ACCOUNT_JSON must be the
# single-line stringified key:  jq -c . < downloaded-key.json

DATABASE_URL="op://Nexion/couple-sync-env/DATABASE_URL"
FIREBASE_PROJECT_ID="op://Nexion/couple-sync-env/FIREBASE_PROJECT_ID"
FIREBASE_SERVICE_ACCOUNT_JSON="op://Nexion/couple-sync-env/FIREBASE_SERVICE_ACCOUNT_JSON"
CORS_ORIGINS="op://Nexion/couple-sync-env/CORS_ORIGINS"
# Optional — admin routes 503 until set.
ADMIN_TOKEN="op://Nexion/couple-sync-env/ADMIN_TOKEN"
# Optional — defaults to 3000.
# PORT="3000"
