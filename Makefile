.PHONY: deps lint test build-web backend-build backend-test

deps:
	flutter pub get
	cd backend && pnpm install --frozen-lockfile

lint:
	dart format --set-exit-if-changed .
	flutter analyze --no-pub
	cd backend && pnpm build

test:
	flutter test --no-pub
	cd backend && pnpm test

build-web:
	flutter build web --no-pub --dart-define-from-file=env/prod.json

backend-build:
	cd backend && pnpm build

backend-test:
	cd backend && pnpm test
