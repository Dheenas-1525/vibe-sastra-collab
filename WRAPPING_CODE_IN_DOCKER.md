# How ViBe is Wrapped in Docker — Without Touching Original Source Code

This document explains exactly how the ViBe application is containerized using Docker.
No original application source code (`backend/src/` or `frontend/src/`) was modified.
Everything described here is purely a deployment/configuration layer placed around the unchanged code.

---

## The Core Idea

Think of Docker as a **box** you place around your application.

- The application code (TypeScript, React) stays exactly as written.
- Docker provides the environment (Node.js runtime, Nginx server) needed to run it.
- Configuration files tell Docker what credentials, ports, and settings to use.
- The original code never knows or cares that it is inside a Docker container.

---

## Repository Layout — What is Original vs. What is Deployment

```
vibe/
├── backend/src/          ← ORIGINAL SOURCE CODE — never touched
├── frontend/src/         ← ORIGINAL SOURCE CODE — never touched
│
├── docker-compose.yml    ← DEPLOYMENT CONFIG — wrapping layer
├── backend.env           ← DEPLOYMENT CONFIG — secrets/settings
├── firebase-service-account.json  ← CREDENTIAL FILE — gitignored, local only
│
├── frontend/
│   ├── Dockerfile        ← DEPLOYMENT CONFIG — build instructions
│   ├── nginx.conf        ← DEPLOYMENT CONFIG — web server rules
│   └── .env              ← DEPLOYMENT CONFIG — gitignored, local only
│
└── self-hosting/         ← GUIDES AND EXAMPLES
```

---

## The Two Containers

Docker Compose runs two containers side by side. They talk to each other over an
internal Docker network called `vibe-network`.

```
┌─────────────────────────────────────────────────────────────────┐
│                        Your Machine                             │
│                                                                 │
│   Browser → port 3000 → [vibe-frontend container]              │
│                                   │                            │
│                           /api/* requests                       │
│                                   │                            │
│                         nginx proxy ↓                          │
│                                   │                            │
│                        [vibe-backend container] ← port 8080    │
│                                   │                            │
│                          MongoDB Atlas (cloud)                  │
│                          Firebase Auth (cloud)                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Container 1: Backend

### How it is obtained

The backend is **built locally from source** (not pulled from Docker Hub).

```yaml
build:
  context: ./backend
  dockerfile: Dockerfile
```

This compiles the TypeScript source in `backend/src/` into JavaScript at `/app/build/`
inside the container. Building from source is required because `WebhookService.ts`
was fixed to read the AI server URL from env vars instead of a hardcoded production IP
— the DockerHub image still has the old hardcoded IP.

### What we configure around it

**1. Startup command override (`docker-compose.yml`)**

The original image ships with a script `start.sh` that runs:
```sh
/app/tailscale up --auth-key="${TAILSCALE_AUTHKEY}" --hostname=gcp
```

Without a Tailscale VPN key, this command blocks forever and Node.js never starts,
causing the container to be reported as "unhealthy."

We override the command in `docker-compose.yml` to make it conditional:
```yaml
command:
  - sh
  - -c
  - >
    /app/tailscaled --tun=userspace-networking --socks5-server=localhost:1055 &
    if [ -n "$$TAILSCALE_AUTHKEY" ]; then
      /app/tailscale up --auth-key="$$TAILSCALE_AUTHKEY" --hostname=gcp;
    fi;
    exec dumb-init node build/index.js
```

Result: Tailscale daemon starts in the background, `tailscale up` only runs when
the key is provided, and Node.js always starts.

**2. Firebase service account volume mount (`docker-compose.yml`)**

The backend verifies user login tokens using Firebase Admin SDK.
In production mode, the SDK uses `applicationDefault()` which reads credentials
from a file path set in the `GOOGLE_APPLICATION_CREDENTIALS` environment variable.

On a Google Cloud server this works automatically. On a local machine it does not
because there is no GCP metadata server. The fix is to mount a service account
JSON file into the container:

```yaml
volumes:
  - ./firebase-service-account.json:/app/firebase-service-account.json:ro
```

The `:ro` flag means read-only — the container can read but not modify the file.

**3. Environment variables (`backend.env`)**

The backend reads all its settings from environment variables. We provide these
via `backend.env`, which is loaded by Docker Compose:

```yaml
env_file:
  - ./backend.env
```

Key variables and what they do:

| Variable | Value | Purpose |
|----------|-------|---------|
| `NODE_ENV` | `production` | Tells the app to load compiled code from `/app/build/modules`. Setting this to `development` would crash — the image has no `/app/src/modules`. |
| `APP_ORIGINS` | `http://localhost:3000,...` | Which browser origins are allowed to call the API (CORS). Must include your frontend URL. |
| `FRONTEND_URL` | `http://localhost:3000/teacher` | Used in email links sent to teachers. |
| `DB_URL` | MongoDB Atlas URI | Connection string to the cloud database. |
| `GOOGLE_APPLICATION_CREDENTIALS` | `/app/firebase-service-account.json` | Path inside the container where Firebase credentials are mounted. |
| `FIREBASE_PROJECT_ID` | `vibe-ffa34` | Firebase project identifier. |
| `FIREBASE_CLIENT_EMAIL` | service account email | Identifies which service account is used. |
| `FIREBASE_PRIVATE_KEY` | RSA private key | Signs requests to Firebase APIs. |

**4. Health check (`docker-compose.yml`)**

Docker checks whether the backend is truly ready before starting the frontend:

```yaml
healthcheck:
  test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:8080/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 60s
```

The `start_period: 60s` gives Node.js 60 seconds to initialize before health check
failures count. The frontend only starts once this check passes:

```yaml
depends_on:
  backend:
    condition: service_healthy
```

---

## Container 2: Frontend

Unlike the backend, the frontend IS built locally from source. The `Dockerfile`
compiles the React application into static files and places them inside an Nginx
web server container.

### The build process (`frontend/Dockerfile`)

```dockerfile
# Stage 1: Build
FROM node:20-alpine AS builder

RUN npm install -g pnpm@10          # install the package manager the project uses

WORKDIR /app

# Copy dependency manifests first (Docker caches this layer until deps change)
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY frontend/package.json ./frontend/

RUN pnpm install --filter frontend --frozen-lockfile   # install dependencies

COPY frontend/ ./frontend/          # copy all React source files

ENV NODE_OPTIONS="--max-old-space-size=8192"   # give Node 8GB RAM for the build
                                                # (Vite needs it for this large app)

RUN pnpm --filter frontend exec vite build     # compile TypeScript + React → static HTML/JS/CSS

# Stage 2: Serve
FROM nginx:stable-alpine
COPY --from=builder /app/frontend/dist /usr/share/nginx/html   # copy built files
COPY frontend/nginx.conf /etc/nginx/conf.d/default.conf        # copy server config
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

**Multi-stage build explained:**
- Stage 1 ("builder") has Node.js, pnpm, all dev dependencies — only used to compile
- Stage 2 ("serve") has only Nginx and the compiled static files — what actually runs
- The final image is tiny because all build tools are discarded after Stage 1

**Why `NODE_OPTIONS=--max-old-space-size=8192`:**
Node.js defaults to ~1.5 GB heap memory. This app has many dependencies and Vite
needs more memory to bundle all the chunks. Without this, `docker-compose build`
crashes with "JavaScript heap out of memory."

**Why `shm_size: '2gb'` in docker-compose.yml:**
Docker containers share a tiny `/dev/shm` (shared memory) by default (64 MB).
Vite's chunk renderer uses shared memory for parallelism. 2 GB prevents OOM crashes
during the build:

```yaml
frontend:
  build:
    shm_size: '2gb'
```

### What the React app receives (`frontend/.env`)

Environment variables starting with `VITE_` are baked into the compiled JavaScript
at build time. The running app cannot read them from the OS — they are hardcoded
into the bundle during `vite build`.

```env
VITE_FIREBASE_API_KEY=...          # Firebase Web SDK — identifies the project in the browser
VITE_FIREBASE_AUTH_DOMAIN=...      # Firebase Auth — where login requests go
VITE_FIREBASE_PROJECT_ID=...       # Firebase project ID used by the browser SDK
VITE_FIREBASE_STORAGE_BUCKET=...   # Firebase Storage bucket for file uploads
VITE_FIREBASE_MESSAGING_SENDER_ID= # Firebase Cloud Messaging sender
VITE_FIREBASE_APP_ID=...           # Unique identifier for this Firebase web app

VITE_BASE_URL=/api                 # All API calls from the browser use this prefix
                                   # /api is relative → Nginx proxies it to the backend

VITE_IS_RECAPTCHA_ENABLED=true     # Tells the signup form to render the reCAPTCHA widget
VITE_RECAPTCHA_SITE_KEY=...        # The public reCAPTCHA key shown in the browser
```

**Important:** If you change anything in `frontend/.env`, you must rebuild the frontend:
```bash
docker compose build frontend && docker compose up -d frontend
```

### How Nginx serves the app (`frontend/nginx.conf`)

Nginx does two jobs:

**Job 1 — Serve the React SPA**
```nginx
location / {
    try_files $uri $uri/ /index.html;
}
```
If a file exists (e.g., `main.js`, `logo.png`) → serve it.
If not → serve `index.html` and let React Router handle the path.
This is how single-page applications work: all page navigation is handled by
JavaScript, not the server.

**Job 2 — Proxy API requests to the backend**
```nginx
location /api {
    proxy_pass http://vibe-backend:8080;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 60s;
}
```
Any request whose URL starts with `/api` is forwarded to `vibe-backend:8080`.
`vibe-backend` is the internal Docker network hostname — it only exists inside
`vibe-network`. The browser never directly contacts the backend.

**Why proxy through Nginx instead of calling the backend directly?**
If the React app called `http://localhost:8080/api` directly, the browser would
block it as a CORS violation (different port = different origin). By proxying
through Nginx on the same origin (port 3000), the browser sees it as a same-origin
request and allows it.

---

## The Full Request Flow

Here is what happens when a logged-in user loads their course list:

```
1. User visits http://localhost:3000/teacher/courses
   → Nginx serves index.html (React SPA)
   → React Router renders the courses page component

2. The page component calls:  GET /api/users/enrollments
   → Browser sends the request to http://localhost:3000/api/users/enrollments
   → Nginx matches location /api → forwards to http://vibe-backend:8080/api/users/enrollments

3. The backend receives the request
   → authorizationChecker reads the Authorization header (Bearer <Firebase JWT>)
   → FirebaseAuthService calls firebase-admin.auth().verifyIdToken(token)
   → Firebase Admin SDK uses GOOGLE_APPLICATION_CREDENTIALS to authenticate
     with Google's servers and verify the token signature
   → Token is valid → user is identified

4. The backend queries MongoDB Atlas
   → Returns the user's enrollment records as JSON

5. JSON travels back:
   backend → nginx → browser → React component renders the data
```

---

## Firebase: Two Different SDKs, Two Different Roles

This is a common point of confusion — Firebase is used in TWO separate places:

| | Frontend (Browser) | Backend (Server) |
|---|---|---|
| SDK | Firebase Web SDK (`firebase` npm package) | Firebase Admin SDK (`firebase-admin` npm package) |
| Config | `VITE_FIREBASE_*` in `frontend/.env` | `GOOGLE_APPLICATION_CREDENTIALS` in `backend.env` |
| Role | Handles user login UI, gets the JWT token | Verifies the JWT token on incoming API requests |
| Credentials | Public API key (safe to expose) | Private service account key (keep secret) |
| Runs in | User's browser | Backend container |

**Login flow:**
1. User enters email/password in the browser
2. Firebase Web SDK sends credentials to Google → gets back a JWT (ID token)
3. Browser stores the JWT and sends it with every API request as `Authorization: Bearer <token>`
4. Backend's Firebase Admin SDK verifies the JWT signature using the private service account key
5. If valid → request is allowed. If invalid/expired → 401 Unauthorized.

---

## What Was Changed in Source

Four backend source files required fixes to make self-hosting work:

- `backend/src/modules/genAI/services/WebhookService.ts` — The vibe-ai server URL
  was hardcoded to a production GCP IP (`34.131.48.163:8017`) instead of reading
  from env vars. Fixed to use `AI_SERVER_IP` and `AI_SERVER_PORT` as intended.

- `backend/src/modules/genAI/services/GenAIService.ts` — Added URL rewriting so
  internal MinIO URLs (`http://minio:9000/...`) are converted to browser-accessible
  relative paths (`/gcs/...`) before being returned to the frontend.

- `backend/src/shared/classes/BaseService.ts` — MongoDB transaction retry logic only
  retried on `TransientTransactionError` labels. Write conflict errors (error code 112)
  do not carry that label and were therefore not retried, causing "uploaded to course
  failed" when publishing a learning module. Fixed to also retry on error code 112,
  with 5 retries and exponential backoff (200 ms, 400 ms, 800 ms…).

- `backend/src/shared/database/providers/mongo/repositories/InviteRepository.ts` —
  The `invites` collection had a `token_unique` unique index without `sparse: true`.
  All SINGLE-type invites have no token (stored as `null`), so MongoDB treated every
  invite as a duplicate after the first one — causing "Failed to create invites" for
  every teacher who tried to send a student invite. Fixed: the `init()` method now
  recreates the index as sparse so only BULK invites (with real token values) compete
  for uniqueness. The bad index was also dropped from the live MongoDB Atlas cluster
  directly via a one-time migration script.

Everything else in `backend/src/` and `frontend/src/` is untouched.
The application reads environment variables at startup — it has no awareness of
whether it is running in Docker, on a bare server, or locally.

---

## Files Changed Summary

| File | Type | What changed | Why |
|------|------|-------------|-----|
| `docker-compose.yml` | Deployment config | Command override, shm_size, volume mount, backend builds from source, MinIO added | Fix Tailscale blocking, fix OOM, provide Firebase credentials, open-source object storage |
| `backend/src/.../WebhookService.ts` | Source fix | Hardcoded IP → env var URL | vibe-ai server was unreachable for self-hosting |
| `backend/src/.../GenAIService.ts` | Source fix | Added URL rewrite (`http://minio:9000/...` → `/gcs/...`) | Browser "Load failed" — internal Docker URLs not reachable from browser |
| `backend/src/shared/classes/BaseService.ts` | Source fix | 5 retries + exponential backoff on WriteConflict (error 112) | "Uploaded to course failed" — MongoDB write conflict not retried during long publish transaction |
| `backend/src/.../InviteRepository.ts` | Source fix | Recreate `token_unique` index as sparse | "Failed to create invites" — non-sparse unique index on null token blocked all inserts after the first |
| `backend/Dockerfile` | Build config | `pnpm tsc` → `pnpm run build` | pnpm v10 binary resolution change |
| `backend/.dockerignore` | New file | Excludes `node_modules` | pnpm workspace symlinks break inside Docker |
| `backend.env` | Secrets/config | Firebase credentials; AI_SERVER_IP/PORT; LLM config; GCS URL rewrite vars | Allow Firebase auth and AI pipeline locally |
| `frontend/Dockerfile` | Build config | Added `ENV NODE_OPTIONS=--max-old-space-size=8192` | Prevent heap OOM during `vite build` |
| `frontend/nginx.conf` | Server config | Added `/api` and `/gcs/` proxy blocks | Route API calls to backend; proxy MinIO files to browser |
| `frontend/.env` | Build-time config | `VITE_BASE_URL=/api`, `VITE_IS_RECAPTCHA_ENABLED=true` | Use nginx proxy path |
| `firebase-service-account.json` | Credential file | New file | Required by Firebase Admin SDK on non-GCP machines |
| `vibe-ai/src/services/question_generation.py` | Source fix | Generate one question per LLM call | Batch generation exceeded token limits — all questions silently failed |
| `vibe-ai/src/ai.py` | Source fix | Removed broken flatten loop | `for i in dict` yields keys not values |
| `vibe-ai/src/services/storage.py` | Rewrite | Replaced `google-cloud-storage` SDK with `minio` SDK | No GCP account needed; MinIO is open-source self-hosted storage |
| `vibe-ai/requirements.txt` | Dependency change | `google-cloud-storage` → `minio>=7.2.0` | Matches storage.py rewrite |
| `vibe-ai/.env` | Config | Replaced GCS vars with MinIO vars | MinIO connection credentials |
| `vibe-ai/Dockerfile` | Build config | Added `PYTHONUNBUFFERED=1` | Background thread logs were invisible in Docker |

---

## Updating from Developer's GitHub

When the developer releases new code, one command handles everything:

```bash
bash update-and-rebuild.sh --git
```

This pulls the latest code from `vicharanashala/vibe` (monorepo) and
`vicharanashala/vibe-ai`, re-applies all 8 deployment patches, rebuilds
the Docker images, restarts containers, and waits for the health check.

See [updating-from-source.md](updating-from-source.md) for the full
explanation of how the update process works.

---

## Quick Reference — Commands

```bash
# First time setup
docker compose build                   # build all containers
docker compose up -d                   # start everything

# Update to latest developer code (pull + patch + rebuild)
bash update-and-rebuild.sh --git

# After changing backend.env (no rebuild needed)
docker compose restart backend

# After changing frontend/.env (rebuild required — env is baked in at build)
docker compose build frontend && docker compose up -d frontend

# Check container status
docker compose ps

# View live logs
docker logs vibe-backend --follow
docker logs vibe-aiserver --follow
docker logs vibe-frontend --follow

# Stop everything
docker compose down

# Full rebuild (clears cached layers)
docker compose build --no-cache backend vibe-aiserver
docker compose up -d
```
