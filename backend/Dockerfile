# syntax=docker/dockerfile:1
# Multi-stage build for couple-sync backend (Node 22, pnpm).
# pnpm version is pinned via `packageManager` in package.json — corepack reads
# it, so no `corepack prepare pnpm@latest` (non-deterministic) here.

FROM node:22-bookworm-slim AS builder
WORKDIR /app
RUN corepack enable
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile
COPY tsconfig.json ./
COPY src ./src
RUN pnpm build

FROM node:22-bookworm-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production
RUN corepack enable
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
RUN pnpm install --prod --frozen-lockfile
COPY --from=builder /app/dist ./dist
COPY src/migrations ./dist/migrations
EXPOSE 3000
# Run migrations (idempotent — CREATE TABLE IF NOT EXISTS) then start the API.
# For multi-replica prod, run `node dist/migrate.js` as a pre-deploy job instead.
CMD ["sh", "-c", "node dist/migrate.js && node dist/index.js"]
