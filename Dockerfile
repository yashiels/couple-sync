# syntax=docker/dockerfile:1
# Coolify web app image: build Flutter web and serve the static bundle.

FROM ghcr.io/cirruslabs/flutter:3.44.0 AS build
WORKDIR /app

COPY pubspec.yaml pubspec.lock .metadata analysis_options.yaml ./
RUN flutter pub get

COPY assets ./assets
COPY env ./env
COPY lib ./lib
COPY web ./web

RUN flutter build web --release --no-wasm-dry-run --dart-define-from-file=env/prod.json

FROM nginx:1.27-alpine
COPY deploy/nginx/flutter-web.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
