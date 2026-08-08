# 1Password-injectable template for the Expo app env (root .env).
# Values are references, not secrets — useless without access to the "Nexion" vault.
# Resolve with:  op inject -i .env.tpl -o .env
# Vault item:    "couple-sync-env" in the Nexion vault (fields are the env-var names)
# See .env.example for prose docs on each var.

API_BASE_URL="op://Nexion/couple-sync-env/API_BASE_URL"
GOOGLE_WEB_CLIENT_ID="op://Nexion/couple-sync-env/GOOGLE_WEB_CLIENT_ID"
