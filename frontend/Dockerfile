FROM node:20-alpine AS builder

# pnpm 10 matches the project (pnpm-lock.yaml lockfileVersion: '9.0')
RUN npm install -g pnpm@10

WORKDIR /app

# ── Layer 1: workspace manifests + lockfile (cached unless deps change) ──────
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY frontend/package.json ./frontend/

# Install only the frontend workspace — devDependencies included by default
RUN pnpm install --filter frontend --frozen-lockfile

# ── Layer 2: source files ─────────────────────────────────────────────────────
COPY frontend/ ./frontend/

# Raise Node heap to 8 GB — required for this large app (README: max-old-space-size=8192)
ENV NODE_OPTIONS="--max-old-space-size=8192"

# Build the production bundle (Vite handles TS transpilation via esbuild)
RUN pnpm --filter frontend exec vite build

# ── Serve with Nginx ──────────────────────────────────────────────────────────
FROM nginx:stable-alpine
COPY --from=builder /app/frontend/dist /usr/share/nginx/html
COPY frontend/nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
