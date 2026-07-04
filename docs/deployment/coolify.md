# Coolify Deployment

Couple Sync runs as two independent Coolify apps from the same GitHub repo and
branch. Keeping them separate lets Coolify rebuild the API and the Flutter web
bundle independently when `main` changes.

## API App

- Name: `couple-sync-api`
- Build pack: Docker Compose
- Compose file: `/docker-compose.yml`
- Domain: `https://api-couple-sync.bumblebeefoundation.co.za`
- Required env:
  - `DATABASE_URL`
  - `FIREBASE_PROJECT_ID`
  - `FIREBASE_SERVICE_ACCOUNT_JSON`
- Optional env:
  - `ADMIN_TOKEN`
  - `CORS_ORIGINS`

`CORS_ORIGINS` defaults to `*`, which works because the app uses Firebase ID
tokens in `Authorization` headers rather than ambient cookies. For production
hardening, set it to a comma-separated allowlist once the web domain is final:

```text
CORS_ORIGINS=https://couple-sync.bumblebeefoundation.co.za,http://localhost:8080
```

## Web App

- Name: `couple-sync-web`
- Build pack: Dockerfile
- Dockerfile: `/Dockerfile`
- Exposed port: `80`
- Domain: choose the final web domain, for example
  `https://couple-sync.bumblebeefoundation.co.za`

The web Dockerfile runs:

```bash
flutter build web --release --no-wasm-dry-run --dart-define-from-file=env/prod.json
```

So web builds pick up `API_BASE_URL` and `WS_URL` from `env/prod.json`. Updating
that file on `main` and pushing will rebuild the web app with the new backend
URLs.

## Auto-Deploy Behavior

In Coolify, both apps should point at:

- Repository: `yashiels/couple-sync`
- Branch: `main`
- Auto deploy: enabled
- Watch paths configured per app

With that setup:

- API-affecting commits rebuild `couple-sync-api`.
- Flutter/web-affecting commits rebuild `couple-sync-web`.
- Shared config changes such as `env/prod.json` rebuild the web app with the
  new API/WebSocket endpoints.

Recommended watch paths:

```text
# couple-sync-api
backend/**
docker-compose.yml

# couple-sync-web
assets/**
env/**
lib/**
web/**
.metadata
Dockerfile
pubspec.yaml
pubspec.lock
deploy/nginx/**
```

After the web app domain is created, add that domain to Firebase Authentication
authorized domains and Google OAuth JavaScript origins if sign-in rejects the
origin.
