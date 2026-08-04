# Build stage: full deps, tsc, and the migrations copy (`pnpm build` does both).
FROM node:22-alpine AS build
WORKDIR /app
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0
RUN corepack enable
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY tsconfig.json ./
COPY src ./src
RUN pnpm build

# Runtime stage: production deps only. A second install rather than a pruned copy of the build
# stage's node_modules, because pnpm's store lives inside node_modules and copying it across
# stages is the fragile option. Ceiling: two installs per image build; fix by caching the pnpm
# store with a BuildKit cache mount if build time ever matters.
FROM node:22-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0
RUN corepack enable
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile --prod
# dist/migrations comes from the build script's `cp -R src/migrations dist/migrations`; migrate.js
# resolves its SQL relative to its own URL, so it must ship inside dist.
COPY --from=build /app/dist ./dist

USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["sh", "-c", "node dist/migrate.js && node dist/index.js"]
