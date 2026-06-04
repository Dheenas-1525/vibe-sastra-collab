# Updating ViBe from the Original Source Code

This document explains how to pull the latest code from the developer's GitHub
repositories, apply all deployment patches, and rebuild Docker containers with
a single command.

---

## Background — Why a Special Update Process?

The developer publishes code to two GitHub repositories:

| Repository | Contains | URL |
|------------|----------|-----|
| `vicharanashala/vibe` | Backend (Node.js) + Frontend (React) as a monorepo | `https://github.com/vicharanashala/vibe` |
| `vicharanashala/vibe-ai` | AI server (Python / FastAPI) | `https://github.com/vicharanashala/vibe-ai` |

The developer's code is written for a **GCP (Google Cloud) production environment**.
Running it locally or on your own server requires 8 patches that fix hardcoded GCP
URLs, replace Google Cloud Storage with MinIO, add MongoDB retry logic, and more.

If you simply pulled the latest code without re-applying these patches, the system
would break. The `update-and-rebuild.sh` script handles this automatically.

---

## The Update Command

Run this one command from anywhere on your machine:

```bash
bash /path/to/vibe/update-and-rebuild.sh --git
```

If you are already inside the `vibe/` folder:

```bash
bash update-and-rebuild.sh --git
```

That's it. The script does everything else automatically.

---

## What the Script Does — Step by Step

```
update-and-rebuild.sh --git
│
├── 1. PULL BACKEND
│      Clones https://github.com/vicharanashala/vibe (monorepo) to /tmp/
│      Copies only the backend/ subfolder into vibe/backend/
│      Deletes the temp clone
│
├── 2. PULL VIBE-AI
│      git pull on vibe-ai/ (already has the correct remote)
│
├── 3. APPLY PATCHES  (calls apply-patches.sh)
│      Copies 9 fixed files from vibe/patches/ over the pulled source:
│      ├── backend/src/modules/genAI/services/WebhookService.ts
│      │     Fix: AI server URL from env var (was hardcoded GCP IP)
│      ├── backend/src/modules/genAI/services/GenAIService.ts
│      │     Fix: Rewrite MinIO URLs → /gcs/... for browser access
│      ├── backend/src/shared/classes/BaseService.ts
│      │     Fix: Retry MongoDB WriteConflict (error 112) with exponential backoff
│      ├── backend/src/shared/database/providers/mongo/repositories/InviteRepository.ts
│      │     Fix: Recreate token_unique index as sparse (fixes "Failed to create invites")
│      ├── vibe-ai/src/services/storage.py
│      │     Fix: Google Cloud Storage SDK → MinIO SDK
│      ├── vibe-ai/src/services/question_generation.py
│      │     Fix: LangChain APIs, max_tokens, one question per LLM call
│      ├── vibe-ai/src/services/transcription.py
│      │     Fix: Cap Whisper model to 'small' (prevents disk fill)
│      ├── vibe-ai/src/routes.py
│      │     Fix: Abort returns 200 (fixes stuck jobs)
│      └── vibe-ai/src/ai.py + requirements.txt
│            Fix: Remove broken flatten loop; google-cloud-storage → minio
│
├── 4. BUILD DOCKER IMAGES
│      docker compose build backend vibe-aiserver
│      (frontend only needs rebuild if UI changed — done separately)
│
├── 5. RESTART CONTAINERS
│      docker compose up -d
│
└── 6. HEALTH CHECK
       Waits up to 3 minutes for vibe-backend to become healthy
       Prints final docker compose ps
```

---

## What Gets Pulled vs. What Stays the Same

| Item | Pulled from GitHub | Kept locally |
|------|-------------------|--------------|
| `backend/src/` | ✅ Replaced from monorepo | — |
| `backend/package.json`, `tsconfig.json` etc. | ✅ Replaced | — |
| `vibe-ai/src/` | ✅ Pulled | — |
| `vibe/patches/` | — | ✅ Never touched |
| `vibe/backend.env` | — | ✅ Your secrets stay |
| `vibe/frontend/.env` | — | ✅ Your secrets stay |
| `vibe/firebase-service-account.json` | — | ✅ Your credentials stay |
| `vibe/docker-compose.yml` | — | ✅ Our config stays |
| `vibe/litellm_config.yaml` | — | ✅ Your LLM config stays |

Your secrets and configuration are **never overwritten** by an update.

---

## Without `--git` Flag

Running without `--git` skips the GitHub pull and only applies patches + rebuilds:

```bash
bash update-and-rebuild.sh
```

Use this when:
- You manually replaced files (e.g., developer sent a ZIP)
- You want to re-apply patches after editing them
- You want to rebuild Docker without pulling new code

---

## Logs

Every run saves a timestamped log to `vibe/update-logs/`:

```
vibe/update-logs/
├── update_2026-06-01_10-30-00.log
├── update_2026-06-02_14-15-42.log
└── update_2026-06-03_17-00-00.log
```

If something fails, open the latest log to see exactly which step failed.

---

## If the Developer Changes a File We Patch

If a developer update changes one of the 8 patched files, our patch will
overwrite their changes. This is intentional — our patches are needed for
self-hosting and must always be applied.

However, if the developer's change was important (e.g., a bug fix in
`question_generation.py`), you need to manually merge their fix into the
corresponding file in `vibe/patches/`.

**How to check if a patch file conflicts:**

```bash
# See what the developer changed in a patched file
diff vibe/patches/vibe-ai/services/question_generation.py \
     vibe-ai/src/services/question_generation.py
```

---

## Folder Structure Reference

```
vibe-new/
├── vibe/                          ← Our Docker wrapper (you are here)
│   ├── update-and-rebuild.sh      ← THE UPDATE COMMAND
│   ├── apply-patches.sh           ← Called automatically by update script
│   ├── patches/                   ← Fixed source files (our deployment fixes)
│   │   ├── backend/
│   │   │   └── src/modules/genAI/services/WebhookService.ts
│   │   │   └── src/modules/genAI/services/GenAIService.ts
│   │   │   └── src/shared/classes/BaseService.ts
│   │   └── vibe-ai/
│   │       └── services/storage.py
│   │       └── services/question_generation.py
│   │       └── services/transcription.py
│   │       └── routes.py
│   │       └── ai.py
│   │       └── requirements.txt
│   ├── backend/                   ← Pulled from vicharanashala/vibe monorepo
│   ├── docker-compose.yml         ← Our deployment config
│   ├── backend.env                ← Your secrets (never overwritten)
│   └── update-logs/               ← Log of every update run
│
└── vibe-ai/                       ← Pulled from vicharanashala/vibe-ai
```

---

## Quick Troubleshooting

**Build fails with "no such host: registry-1.docker.io"**
→ Docker Desktop lost internet access. Restart Docker Desktop and try again.
If still failing, run without `--no-cache` — Docker uses cached base images:
```bash
docker compose build backend vibe-aiserver
```

**Backend stuck at "starting" after rebuild**
→ MongoDB is slow to reconnect after a restart. Wait 60–90 seconds. Check:
```bash
docker logs vibe-backend 2>&1 | grep -E "healthy|Error|Startup"
```

**Patch fails with "No such file or directory"**
→ The developer renamed or moved a file we patch. Check the new path and update
`apply-patches.sh` accordingly.

**Want to undo an update**
→ The old Docker images are still cached. Re-tag and restart:
```bash
docker images | grep vibe-backend        # find the old IMAGE ID
docker tag <OLD_IMAGE_ID> vibe-backend:rollback
# edit docker-compose.yml: image: vibe-backend:rollback
docker compose up -d backend
```
