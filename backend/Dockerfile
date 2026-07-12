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
# Run as non-root. node:22-bookworm-slim ships a `node` user (uid 1000).
# chown runs AFTER all COPYs so every file under /app is owned by node.
RUN chown -R node:node /app
USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
# Run migrations (idempotent — CREATE TABLE IF NOT EXISTS) then start the API.
# For multi-replica prod, run `node dist/migrate.js` as a pre-deploy job instead.
CMD ["sh", "-c", "node dist/migrate.js && node dist/index.js"]
