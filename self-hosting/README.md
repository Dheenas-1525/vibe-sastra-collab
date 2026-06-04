

# Vibe — Setup & Deployment Guide

## Introduction

Vibe is a full-stack application consisting of three services: a **React/Vite frontend**, a **Node.js backend** (distributed as a Docker image), and an **AI server** that powers Claude-based features.

This guide covers setting up and deploying the frontend and backend. The AI server is a separate service — setup instructions for it can be found at [github.com/vicharanashala/vibe-ai](https://github.com/vicharanashala/vibe-ai.git). If you do not have access to the AI server or are running locally, you can disable AI features by omitting the `AI_SERVER_IP`, `AI_SERVER_PORT`, and `AI_PROXY_ADDRESS` environment variables in the backend configuration.

### Architecture Overview

| Service | Technology | Deployment |
|---|---|---|
| Frontend | React + Vite | Static files (Nginx / CDN) |
| Backend | Node.js | Docker container |
| AI Server | Python (self-hosted) | See [vibe-ai](https://github.com/vicharanashala/vibe-ai.git) |

The backend exposes a REST API that the frontend communicates with. The AI server is accessed by the backend over a private Tailscale network, and is only required if you intend to use AI-powered features.

---





# Frontend — Setup & Deployment Guide

## Prerequisites
- Node.js (v18+)
- npm

---

## 1. Install pnpm

```bash
sudo npm install -g pnpm
```

> If you get a version mismatch error, run this first:
> ```bash
> rm -rf ~/Library/pnpm
> sudo npm uninstall -g pnpm
> sudo npm install -g pnpm
> ```

---

## 2. Install Dependencies

Navigate to the frontend directory and install:

```bash
cd frontend
pnpm install
```

---

## 3. Configure Environment Variables

Create a `.env` file inside the `frontend/` directory:

```bash
cp .env.example .env
```

Then fill in the values:

```dotenv
# Firebase Configuration
# Get these from Firebase Console → Project Settings → Your Apps → SDK config
VITE_FIREBASE_API_KEY=
VITE_FIREBASE_AUTH_DOMAIN=
VITE_FIREBASE_PROJECT_ID=
VITE_FIREBASE_STORAGE_BUCKET=
VITE_FIREBASE_MESSAGING_SENDER_ID=
VITE_FIREBASE_APP_ID=
VITE_FIREBASE_MEASUREMENT_ID=

# Backend API URL
# URL of the running backend instance, with /api suffix
# Example: https://your-backend-domain.com/api
VITE_BASE_URL=

# Google reCAPTCHA Site Key
# Get this from GCP Console → Security → reCAPTCHA
VITE_RECAPTCHA_SITE_KEY=
```

### Where to get each value

| Variable | Source |
|---|---|
| `VITE_FIREBASE_API_KEY` | Firebase Console → Project Settings → Your Apps → SDK config |
| `VITE_FIREBASE_AUTH_DOMAIN` | Same as above — format: `your-project-id.firebaseapp.com` |
| `VITE_FIREBASE_PROJECT_ID` | Same as above — your Firebase project ID |
| `VITE_FIREBASE_STORAGE_BUCKET` | Same as above — format: `your-project-id.appspot.com` |
| `VITE_FIREBASE_MESSAGING_SENDER_ID` | Same as above — numeric sender ID |
| `VITE_FIREBASE_APP_ID` | Same as above — format: `1:xxx:web:xxx` |
| `VITE_FIREBASE_MEASUREMENT_ID` | Same as above — format: `G-XXXXXXXX` (Google Analytics) |
| `VITE_BASE_URL` | URL of your running backend + `/api` suffix |
| `VITE_RECAPTCHA_SITE_KEY` | [GCP Console](https://console.cloud.google.com) → Security → reCAPTCHA |

---

## 4. Production Build

### Step 1 — Verify `.env` is present and complete

```bash
# Ensure you are inside the frontend directory
cd frontend

# Confirm .env file exists
ls -la .env

# Review all values are filled — no empty assignments
cat .env
```

Make sure **no values are empty**. Vite reads and injects all `VITE_*` variables at **build time**, not runtime. Once `dist/` is generated, the env values are permanently baked into the static files.

> **Changing `.env` after the build has no effect.** If you need to point to a different backend or use different credentials, update `.env` and rebuild.

### Step 2 — Run the build

```bash
NODE_OPTIONS="--max-old-space-size=8192" npx vite build
```

> The increased memory limit is required due to the size of the dependency tree.

Output is generated in `frontend/dist/`.

---

## 5. Serve the Production Build

The `dist/` folder contains fully static files and can be served by any static file server or CDN.

**Using a simple local server to verify the build:**

```bash
npx serve dist
```

**Using Nginx (example config):**

```nginx
server {
    listen 80;
    server_name your-domain.com;
    root /path/to/frontend/dist;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

> The `try_files` directive is required for client-side routing to work correctly. Without it, directly accessing any route other than `/` will return a 404.

---

## Notes

- The `dist/` folder is fully self-contained with all env values baked in at build time.
- Peer dependency warnings during `pnpm install` (React 19 vs older packages) are expected and non-blocking.
- Asset warnings for `/public/img/*` during dev are non-blocking.

---

## Quick Reference

| Step | Command |
|---|---|
| Install pnpm | `sudo npm install -g pnpm` |
| Install dependencies | `cd frontend && pnpm install` |
| Setup env | `cp .env.example .env` then fill values |
| Production build | `NODE_OPTIONS="--max-old-space-size=8192" npx vite build` |
| Verify build locally | `npx serve dist` |








---
---










# Backend — Setup & Deployment Guide

## Prerequisites
- Docker installed — [Get Docker](https://docs.docker.com/get-docker/)

---

## 1. Pull the Docker Image

The backend is published to Docker Hub under `vicharanashala/vibe-backend`.

```bash
docker pull vicharanashala/vibe-backend:staging
```

Check available tags at: [hub.docker.com/r/vicharanashala/vibe-backend](https://hub.docker.com/r/vicharanashala/vibe-backend)

---

## 2. Configure Environment Variables

Create an `env.list` file with the following variables filled in:

```dotenv
# ── Server ────────────────────────────────────────────────
# Node environment (use "production" for prod)
NODE_ENV=production

# Port the app listens on inside the container
APP_PORT=8080

# Publicly accessible URL of this backend instance
APP_URL=https://your-backend-domain.com

# Comma-separated list of allowed CORS origins
APP_ORIGINS=https://your-frontend-domain.com,http://localhost:5173

# Route prefix for all API endpoints (do not change unless necessary)
APP_ROUTE_PREFIX=/api

# Which app module to load — use "all" unless running split services
APP_MODULE=all

# URL used in emails or redirects pointing back to the frontend
FRONTEND_URL=https://your-frontend-domain.com/teacher

# Admin panel password
ADMIN_PASSWORD=your-secure-password

# ── Database ──────────────────────────────────────────────
# MongoDB connection string
DB_URL=mongodb+srv://user:password@cluster.mongodb.net

# MongoDB database name
DB_NAME=vibe

# ── AI / Anthropic ────────────────────────────────────────
# Anthropic Claude model to use
ANTHROPIC_MODEL=claude-sonnet-4-20250514

# Anthropic API key
ANTHROPIC_CRED=sk-ant-...

# Internal AI server host (if using a self-hosted AI service over Tailscale)
AI_SERVER_IP=100.x.x.x

# Internal AI server port
AI_SERVER_PORT=8017

# SOCKS5 proxy address used to route traffic to the AI server via Tailscale
AI_PROXY_ADDRESS=socks5h://localhost:1055

# ── reCAPTCHA ─────────────────────────────────────────────
# Secret key from GCP Console → Security → reCAPTCHA
RECAPTCHA_SECRET_KEY=your-recaptcha-secret

# Enable or disable reCAPTCHA validation
IS_RECAPTCHA_ENABLED=true

# ── Monitoring ────────────────────────────────────────────
# Sentry DSN for error tracking — leave empty to disable
SENTRY_DSN=https://xxx@sentry.io/xxx

# ── Backup ────────────────────────────────────────────────
# Enable automated database backups to GCP Storage
ENABLE_DB_BACKUP=true

# GCP bucket name for database backups
GCP_BACKUP_BUCKET=vibe-backup-data

# GCP bucket name for storing user activity/submissions
GCP_BACKUP_ACTIVITY_BUCKET=vibe-submissions

# ── Tailscale ─────────────────────────────────────────────
# Tailscale auth key — required only if AI server is accessed over Tailscale VPN
TAILSCALE_AUTHKEY=tskey-auth-...

# ── HP Job ────────────────────────────────────────────────
# Enable background job for HP (high priority) task processing
ENABLE_HP_JOB=true
```

---

## 3. Run the Container

```bash
docker run -d \
  --name vibe-backend \
  --env-file env.list \
  -p 8080:8080 \
  vicharanashala/vibe-backend:staging
```

The backend will be available at `http://localhost:8080/api`.

### Verify it's running

```bash
docker logs -f vibe-backend
```

---

## 4. Environment Variable Reference

| Variable | Required | Description |
|---|---|---|
| `NODE_ENV` | ✅ | Runtime environment — set to `production` |
| `APP_PORT` | ✅ | Port the server listens on inside the container |
| `APP_URL` | ✅ | Publicly accessible URL of this backend instance |
| `APP_ORIGINS` | ✅ | Comma-separated allowed CORS origins |
| `APP_ROUTE_PREFIX` | ✅ | API route prefix — default `/api` |
| `APP_MODULE` | ✅ | Module to load — use `all` |
| `FRONTEND_URL` | ✅ | Frontend URL used in emails and redirects |
| `ADMIN_PASSWORD` | ✅ | Password for the admin panel |
| `DB_URL` | ✅ | MongoDB connection string |
| `DB_NAME` | ✅ | MongoDB database name |
| `ANTHROPIC_MODEL` | ✅ | Claude model identifier |
| `ANTHROPIC_CRED` | ✅ | Anthropic API key |
| `AI_SERVER_IP` | ⚠️ | Internal AI server IP — required only if using self-hosted AI over Tailscale |
| `AI_SERVER_PORT` | ⚠️ | Internal AI server port — required only if using self-hosted AI |
| `AI_PROXY_ADDRESS` | ⚠️ | SOCKS5 proxy for Tailscale tunnel to AI server |
| `TAILSCALE_AUTHKEY` | ⚠️ | Tailscale auth key — required only if AI server is on a private network |
| `RECAPTCHA_SECRET_KEY` | ✅ | reCAPTCHA secret key from GCP Console |
| `IS_RECAPTCHA_ENABLED` | ✅ | Set `true` to enforce reCAPTCHA, `false` to skip |
| `SENTRY_DSN` | ❌ | Sentry error tracking DSN — leave empty to disable |
| `ENABLE_DB_BACKUP` | ❌ | Set `true` to enable scheduled DB backups to GCP |
| `GCP_BACKUP_BUCKET` | ⚠️ | GCP bucket for DB backups — required if `ENABLE_DB_BACKUP=true` |
| `GCP_BACKUP_ACTIVITY_BUCKET` | ⚠️ | GCP bucket for user submissions — required if `ENABLE_DB_BACKUP=true` |
| `ENABLE_HP_JOB` | ❌ | Set `true` to enable background high-priority job processing |

> ✅ Required — ⚠️ Conditionally required — ❌ Optional

---

## Notes

- The backend API is accessible at `APP_URL + APP_ROUTE_PREFIX` (e.g. `https://your-domain.com/api`). Use this as the `VITE_BASE_URL` in the frontend `.env`.
- `AI_SERVER_IP`, `AI_SERVER_PORT`, `AI_PROXY_ADDRESS`, and `TAILSCALE_AUTHKEY` are only needed if you are running the self-hosted AI service on a private Tailscale network. Contributors without access to this can disable AI features or point to an alternative.
- Backup variables require GCP credentials to be configured inside the container or via a service account. Contributors running locally can safely set `ENABLE_DB_BACKUP=false`.
