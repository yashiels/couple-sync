# 1Password-injectable template for the Expo app env (root .env).
# Values are references, not secrets — useless without access to the "Nexion" vault.
# Resolve with:  op inject -i .env.tpl -o .env
# Source: the single "couple-sync" item in the Nexion vault (referenced by UUID).
# See .env.example for prose docs on each var.

API_BASE_URL="op://Nexion/rn47nl5ayzg2cztuw4tmizbrvi/api_base_url"
GOOGLE_WEB_CLIENT_ID="op://Nexion/rn47nl5ayzg2cztuw4tmizbrvi/google_web_client_id"
