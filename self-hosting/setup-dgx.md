# ViBe — DGX Server Setup: Known Issues & Fixes

This document records every conflict and error encountered when deploying ViBe on the DGX server (`dgx-node1`), and exactly how each was resolved.

---

## Environment

| Item | Value |
|---|---|
| Server | `dgx-node1` — NVIDIA DGX |
| Server IP | `172.16.13.91` |
| User | `dheena_vibe` |
| Home path | `/nfsshare/users/dheena_vibe/` |
| Repo path | `/nfsshare/users/dheena_vibe/vibe-sastra-collab/` |
| Docker version | Old — uses `docker-compose` not `docker compose` |

---

## Issue 1 — `vibe-ai/.env not found` when building frontend

### Error
```
env file /nfsshare/users/dheena_vibe/vibe-ai/.env not found:
stat /nfsshare/users/dheena_vibe/vibe-ai/.env: no such file or directory
```

### Cause
`docker-compose.yml` referenced `../vibe-ai/.env` — a sibling directory outside the repo. `vibe-ai` was never part of the git repo, so it didn't exist on the server after cloning.

### Fix
Moved `vibe-ai/` inside the repo:
- Copied all `vibe-ai` source files into `vibe/vibe-ai/`
- Updated `docker-compose.yml`: `context: ../vibe-ai` → `context: ./vibe-ai`
- Added `vibe-ai/.env.example` as a template (committed)
- Added `vibe-ai/.env` to `.gitignore` (secrets stay local)

**After clone, user must run:**
```bash
cp vibe-ai/.env.example vibe-ai/.env
nano vibe-ai/.env   # fill in GPU server IP and MinIO password
```

---

## Issue 2 — `frontend/package.json not found` during Docker build

### Error
```
failed to solve: failed to compute cache key:
"/frontend/package.json": not found
```

### Cause
`frontend/.gitignore` had `package.json` listed — so it was never committed to the repo. The Docker build context couldn't find it.

### Fix
Removed `package.json` from `frontend/.gitignore` and force-added it to git:
```bash
git add -f frontend/package.json
git commit -m "fix: include frontend/package.json in repo"
```

---

## Issue 3 — Port 3000 already in use

### Error
```
failed to bind port 0.0.0.0:3000/tcp:
Error starting userland proxy: listen tcp4 0.0.0.0:3000: bind: address already in use
```

### Cause
Another process was already using port 3000 on the DGX server.

### Fix
Find and kill the process:
```bash
sudo lsof -i :3000
sudo kill -9 <PID>
docker-compose up -d frontend
```

Or change the port in `docker-compose.yml`:
```yaml
ports:
  - "3001:80"   # change 3000 to any free port
```

---

## Issue 4 — No browser on server — how to access frontend

### Situation
DGX server has no GUI or browser. Frontend runs at port 3000 but can't be opened directly.

### Fix — Direct IP (same network)
Since the local Mac (`172.16.13.100`) and the server (`172.16.13.91`) are on the same network:
```
http://172.16.13.91:3000
```

### Fix — SSH tunnel (different network)
```bash
ssh -L 3000:localhost:3000 dheena_vibe@172.16.13.91
# Then open http://localhost:3000 on local Mac
```

---

## Issue 5 — reCAPTCHA: "Invalid domain for site key"

### Error
```
ERROR for site owner: Invalid domain for site key
```

### Cause
The reCAPTCHA site key was registered for specific domains. The server IP `172.16.13.91` was not in the allowed list.

### Fix — Add IP to reCAPTCHA
Go to [https://www.google.com/recaptcha/admin](https://www.google.com/recaptcha/admin) → your site → Settings → Domains → add `172.16.13.91` → Save.

### Fix — Disable reCAPTCHA for testing (faster)
In `backend.env`:
```env
IS_RECAPTCHA_ENABLED=false
```
In `frontend/.env`:
```env
VITE_IS_RECAPTCHA_ENABLED=false
```
Then rebuild frontend:
```bash
docker-compose build frontend
docker-compose up -d
```

---

## Issue 6 — Firebase: "Failed to sign in with Google" / Invalid domain

### Error
```
Failed to sign in with Google. Please try again.
The following domain is invalid: http://172.16.13.91:3001.
A valid domain requires a host and must not include any protocol, path, port, query or fragment.
```

### Cause
The server IP was not in Firebase's Authorized Domains list. Firebase rejects login attempts from unregistered domains.

### Fix
Go to **Firebase Console → Authentication → Settings → Authorized Domains → Add domain**.

Enter only the bare IP — no `http://`, no port:
```
172.16.13.91
```

---

## Issue 7 — MongoDB Atlas: IP not whitelisted

### Cause
MongoDB Atlas blocks connections from IPs not in the Network Access whitelist. The DGX server IP was not added.

### Fix — Allow all IPs permanently
Go to **MongoDB Atlas → Network Access → Add IP Address → Allow Access from Anywhere**.

This sets `0.0.0.0/0` — any IP can connect. Avoids having to update the whitelist every time the server IP changes.

Then update `backend.env` with the Atlas connection string:
```env
DB_URL=mongodb+srv://username:password@cluster0.xxxxx.mongodb.net/?retryWrites=true&w=majority
DB_NAME=vibe
```

---

## Issue 8 — All API calls return 401 "Authorization is required"

### Error (backend logs)
```
Message: Authorization is required for request on GET /api/course/...
Message: Authorization is required for request on GET /api/notifications/...
```

### Cause
The backend uses Firebase Admin SDK to verify user tokens. The `firebase-service-account.json` file was missing from the server — the backend could not verify any Firebase JWT token, so every authenticated request returned 401.

### Fix
Copy the file from local Mac to server:
```bash
# Run on local Mac
scp /path/to/vibe/firebase-service-account.json \
    dheena_vibe@172.16.13.91:/nfsshare/users/dheena_vibe/vibe-sastra-collab/
```

Verify it exists and is a file (not a directory):
```bash
ls -lh /nfsshare/users/dheena_vibe/vibe-sastra-collab/firebase-service-account.json
# Should show: -rw-r--r-- ... 2.3K ... firebase-service-account.json
```

Verify `backend.env` has:
```env
GOOGLE_APPLICATION_CREDENTIALS=/app/firebase-service-account.json
```

Verify `docker-compose.yml` has the volume mount under `backend`:
```yaml
volumes:
  - ./firebase-service-account.json:/app/firebase-service-account.json:ro
```

Then restart:
```bash
docker-compose up -d backend
```

> **Note:** `firebase-service-account.json` is in `.gitignore` — it contains a private key and must NEVER be committed. Copy it manually to every server.

---

## Issue 9 — `firebase-service-account.json` created as directory instead of file

### Error
```
scp: dest open "vibe-sastra-collab/firebase-service-account.json": Failure
scp: failed to upload file ...
```

After the failed scp, the path became an empty directory instead of a file:
```bash
ls -la vibe-sastra-collab/firebase-service-account.json
# Shows: drwxr-xr-x (directory!)
```

### Cause
The first `scp` failed silently but left an empty directory at the destination path.

### Fix
Remove the directory and copy again with the full absolute path:
```bash
# On server — remove the bad directory
rm -rf /nfsshare/users/dheena_vibe/vibe-sastra-collab/firebase-service-account.json

# On local Mac — copy with full absolute destination path
scp /path/to/firebase-service-account.json \
    dheena_vibe@172.16.13.91:/nfsshare/users/dheena_vibe/vibe-sastra-collab/firebase-service-account.json
```

---

## Issue 10 — `docker: 'compose' is not a docker command`

### Error
```
docker: 'compose' is not a docker command.
```

### Cause
The DGX server runs an older version of Docker that does not include the `compose` subcommand. The new syntax is `docker compose` (space) but old Docker requires `docker-compose` (hyphen).

### Fix
`update-and-rebuild.sh` was updated to use `docker-compose` throughout.

For manual commands, always use:
```bash
docker-compose build
docker-compose up -d
docker-compose ps
docker-compose logs
```

---

## Issue 11 — Camera/microphone blocked on HTTP

### Message
```
Please allow camera and microphone access to continue.
You will be redirected to the dashboard if access is denied.
```

### Cause
Browsers block camera/microphone access on plain `http://` connections (non-localhost). Security policy requires `https://` or `localhost` for media device access.

### Fix A — Chrome flag (for testing)
1. Open Chrome and go to: `chrome://flags/#unsafely-treat-insecure-origin-as-secure`
2. Add `http://172.16.13.91:3000` to the list
3. Set to **Enabled** → Relaunch Chrome

### Fix B — SSH tunnel (access via localhost)
```bash
ssh -L 3000:localhost:3000 dheena_vibe@172.16.13.91
```
Then open `http://localhost:3000` — browsers always allow camera/mic on localhost.

### Fix C — HTTPS (production)
Set up a domain with SSL (Nginx + Certbot). See `self-hosting/DEPLOYMENT_GUIDE.md` Phase 8.

---

## Final Working Setup Checklist

After resolving all issues above, this is the confirmed working state:

```
✅ vibe-ai/ is inside the repo (no separate clone needed)
✅ frontend/package.json committed (was gitignored before)
✅ docker-compose.yml uses ./vibe-ai (not ../vibe-ai)
✅ update-and-rebuild.sh uses docker-compose (not docker compose)
✅ MongoDB Atlas: 0.0.0.0/0 whitelisted — no IP management needed
✅ Firebase: 172.16.13.91 added to Authorized Domains
✅ reCAPTCHA: disabled for internal testing
✅ firebase-service-account.json: copied manually via scp
✅ vibe-ai/.env: created from .env.example, GPU server IP set
✅ frontend accessible at http://172.16.13.91:3000
```

## Files That Must Be Copied Manually to Every Server

These are in `.gitignore` — never committed — must be transferred via `scp`:

| File | Contains | Command |
|---|---|---|
| `firebase-service-account.json` | Firebase private key | `scp firebase-service-account.json dheena_vibe@172.16.13.91:~/vibe-sastra-collab/` |
| `backend.env` | DB URL, API keys, Firebase config | `scp backend.env dheena_vibe@172.16.13.91:~/vibe-sastra-collab/` |
| `frontend/.env` | Firebase public keys, backend URL | `scp frontend/.env dheena_vibe@172.16.13.91:~/vibe-sastra-collab/frontend/` |
| `vibe-ai/.env` | GPU server URL, MinIO credentials | `scp vibe-ai/.env dheena_vibe@172.16.13.91:~/vibe-sastra-collab/vibe-ai/` |
