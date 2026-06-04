# Source Code Changes — What Was Modified and Why

This document records every change made to the original ViBe source code during
local self-hosting setup. Full transparency: exact diffs, what changed, and why.

---

## Summary

| Repo | File | Type | Reason |
|------|------|------|--------|
| `vibe` | `backend/src/modules/genAI/services/WebhookService.ts` | Bug fix | Hardcoded production IP blocked all AI server routing |
| `vibe` | `backend/Dockerfile` | Bug fix | pnpm v10 broke the `pnpm tsc` command |
| `vibe` | `backend/.dockerignore` | New file | pnpm workspace symlinks corrupted Docker build |
| `vibe-ai` | `requirements.txt` | Bug fix | Missing LangChain packages that the code imports |
| `vibe-ai` | `src/services/question_generation.py` | Bug fix | Imports non-existent LangChain APIs — server could not start |
| `vibe-ai` | `src/services/question_generation.py` | Bug fix | No `max_tokens` set — LLM truncated JSON mid-output |
| `vibe-ai` | `src/services/question_generation.py` | Bug fix | Generating N questions in one call exceeded max_tokens; now generates one at a time |
| `vibe-ai` | `src/ai.py` | Bug fix | Flatten logic iterated over dict keys instead of values for single-question results |
| `vibe-ai` | `src/services/transcription.py` | Safety fix | `large` model (10GB) filled disk — capped to `small` |
| `vibe-ai` | `src/routes.py` | Bug fix | Abort endpoint returned 404 after restart, blocking retries |
| `vibe-ai` | `src/services/storage.py` | Rewrite | Replaced GCS SDK with MinIO SDK; retained `delete_job_files()` |
| `vibe-ai` | `Dockerfile` | Fix | `PYTHONUNBUFFERED=1` missing — Docker logs showed nothing from background threads |
| `vibe` | `backend/src/modules/genAI/services/GenAIService.ts` | Bug fix | Frontend received internal Docker URLs (`http://minio:9000/...`) — browser "Load failed". Added URL rewrite to `/gcs/...` |
| `vibe` | `frontend/nginx.conf` | Enhancement | Added `/gcs/` proxy location to serve MinIO files through Nginx |
| `vibe` | `backend/src/shared/classes/BaseService.ts` | Bug fix | MongoDB WriteConflict (error 112) not retried — caused "Uploaded to course failed" on publish. Fixed: 5 retries with exponential backoff. |
| `vibe` | `backend/src/shared/database/providers/mongo/repositories/InviteRepository.ts` | Bug fix | `token_unique` index was non-sparse — all SINGLE invites had `token: null`, only one could ever be inserted. Fixed: drop old index, recreate as `sparse: true`. |

**New files created (not changes to existing code):**
- `vibe-ai/Dockerfile` — vibe-ai had no Dockerfile; required for Docker deployment
- `vibe-ai/.env` — configuration for the Docker container
- `vibe/litellm_config.yaml` — LiteLLM routing config for local LLM

**Infrastructure additions (docker-compose.yml):**
- `minio` service — open-source S3-compatible object storage (no cloud account needed)

---

## Change 1 — `backend/src/modules/genAI/services/WebhookService.ts`

### What it does
`WebhookService` sends HTTP requests to the vibe-ai server to control the video
processing pipeline (audio extraction, Whisper transcription, segmentation, question generation).

### The problem
The original code had the correct env-var URL written — but commented out —
and replaced with a hardcoded production GCP IP:

```typescript
// ORIGINAL CODE (before change):
this.httpClient = axios.create({
  // baseURL: this.aiServerUrl,           ← correct line — COMMENTED OUT
  baseURL: "http://34.131.48.163:8017",  ← hardcoded ViBe production server IP
  timeout: 30000,
});
```

Because the hardcoded IP was active, even if you set `AI_SERVER_IP` in `.env`,
it was completely ignored. All genAI requests went to ViBe's private GCP server.
When self-hosting locally, that server is unreachable — all video AI features
silently fail or time out.

### The fix

```typescript
// CHANGED CODE (after):
this.httpClient = axios.create({
  baseURL: this.aiServerUrl,               // ← now reads from env vars
  // baseURL: "http://34.131.48.163:8017"  // ← kept as comment for reference
  timeout: 30000,
});
```

Also removed now-unused imports `SocksProxyAgent`, `appConfig`, and the dead
`agent` variable.

### Why this is safe
The env-var URL was already written in the original code — just accidentally
commented out. This restores the intended design. `AI_SERVER_IP` and
`AI_SERVER_PORT` are documented in the backend README as official config variables.

---

## Change 2 — `backend/Dockerfile`

### The problem
The original Dockerfile had:
```dockerfile
RUN pnpm tsc
```

With pnpm v10, `pnpm tsc` no longer finds the TypeScript binary inside
`node_modules/.bin/`. The build failed with:

```
Error: Cannot find module '/app/node_modules/typescript/bin/tsc'
```

### The fix
```dockerfile
# BEFORE:
RUN pnpm tsc

# AFTER:
RUN pnpm run build
```

`pnpm run build` runs the `"build": "tsc"` script defined in `package.json`,
which pnpm v10 resolves correctly.

---

## Change 3 — `backend/.dockerignore` (new file)

### The problem
The `vibe` project is a **pnpm workspace**. When you run `pnpm install`, pnpm
creates symlinks inside `vibe/backend/node_modules/` pointing to the workspace
store at `../../node_modules/.pnpm/...`. That path is outside the Docker build
context, so inside the container the symlinks are broken.

### The fix
Created `backend/.dockerignore` to exclude `node_modules` from being copied.
Docker installs packages fresh during build, where all paths are valid.

```
node_modules
build
.env
*.md
```

---

## Change 4 — `vibe-ai/requirements.txt`

### The problem
The original `requirements.txt` was missing two packages that `question_generation.py`
directly imports at the top of the file:

```python
from langchain_openai import ChatOpenAI      # ← langchain-openai not listed
from langchain_core.messages import ...      # ← langchain-core not listed
```

### The fix
Added two missing packages:
```
langchain-openai>=0.3.0
langchain-core>=0.3.0
```

---

## Change 5 — `vibe-ai/src/services/question_generation.py` (broken imports)

### The problem
The original file imported two modules that **do not exist** in any released
version of LangChain:

```python
# ORIGINAL — both lines crash with ModuleNotFoundError at startup:
from langchain.agents import create_agent                        # does not exist
from langchain.agents.structured_output import ToolStrategy      # does not exist
```

The server crashed immediately on startup — before accepting any request — with:

```
ModuleNotFoundError: No module named 'langchain.agents.create_agent'
```

The `_build_agent` method also used these non-existent functions:

```python
# ORIGINAL — crashes at runtime:
def _build_agent(self, model, schema, system_prompt):
    return create_agent(
        model=model,
        tools=[],
        response_format=ToolStrategy(schema),
        system_prompt=system_prompt,
    )

agent = self._build_agent(model, schema, system_prompt)
result = await agent.ainvoke({"messages": [{"role": "user", "content": prompt_text}]})
questions = self._unwrap_questions(result["structured_response"], count)
```

### The fix
Replaced broken imports with real stable LangChain modules:

```python
# BEFORE (broken):
from langchain.agents import create_agent
from langchain.agents.structured_output import ToolStrategy

# AFTER (works):
from langchain_core.messages import SystemMessage, HumanMessage
import re
```

Replaced `_build_agent` with `_invoke_structured`:

```python
async def _invoke_structured(self, model, schema, system_prompt, prompt_text):
    schema_str = json.dumps(schema, indent=2)
    messages = [
        SystemMessage(content=(
            f"{system_prompt}\n\n"
            "Respond ONLY with a valid JSON object that matches this schema "
            "(no markdown, no extra text):\n"
            f"{schema_str}"
        )),
        HumanMessage(content=prompt_text),
    ]
    response = await model.ainvoke(messages)
    text = response.content.strip()
    match = re.search(r"```(?:json)?\s*([\s\S]*?)```", text)
    if match:
        text = match.group(1).strip()
    return json.loads(text)
```

Updated call site:

```python
# BEFORE:
agent = self._build_agent(model, schema, system_prompt)
result = await agent.ainvoke({"messages": [{"role": "user", "content": prompt_text}]})
questions = self._unwrap_questions(result["structured_response"], count)

# AFTER:
result = await self._invoke_structured(model, schema, system_prompt, prompt_text)
questions = self._unwrap_questions(result, count)
```

---

## Change 6 — `vibe-ai/src/services/question_generation.py` (max_tokens)

### The problem
`ChatOpenAI` was instantiated without `max_tokens`. LM Studio uses a default of
~2048 output tokens. Generating 10 SOL questions requires ~4000+ tokens. The model
cut off its response mid-JSON, causing:

```
Error generating SOL questions for segment 142.4: Expecting ',' delimiter: line 312 column 5 (char 10883)
```

### The fix
Added `max_tokens=4096` to both `ChatOpenAI` instantiations:

```python
# BEFORE:
self.model = ChatOpenAI(
    model=self.DEFAULT_MODEL,
    base_url=vllm_base_url,
    api_key="EMPTY",
    temperature=0,
    timeout=300,
)

# AFTER:
self.model = ChatOpenAI(
    model=self.DEFAULT_MODEL,
    base_url=vllm_base_url,
    api_key="EMPTY",
    temperature=0,
    timeout=300,
    max_tokens=4096,
)
```

Same change applied to the `_get_model` method.

---

## Change 7 — `vibe-ai/src/services/transcription.py` (Whisper model cap)

### The problem
The UI sends `modelSize: 'large'` by default. Whisper `large` is a 10GB model.
When the container started downloading it, the Mac's disk filled to 99%, Docker
crashed with I/O errors, and the entire stack went down.

### The fix
Added a safety cap in `transcription.py` that maps any model above `small` down
to `small` before passing it to Whisper:

```python
# ADDED — caps model size before loading:
safe_sizes = {'tiny', 'base', 'small'}
effective_size = model_size if model_size in safe_sizes else 'small'
if effective_size != model_size:
    print(f"Model size '{model_size}' capped to 'small' for local deployment")

await self._load_model(effective_size)
```

Also changed `verbose=True` → `verbose=False` in the Whisper call to reduce log noise.

**Whisper model sizes for reference:**

| Model | RAM needed | Speed (CPU) |
|-------|-----------|------------|
| `tiny` | ~1 GB | Very fast |
| `base` | ~1 GB | Fast |
| `small` | ~2 GB | Moderate — recommended for local |
| `medium` | ~5 GB | Slow |
| `large` | ~10 GB | Very slow — fills disk |

---

## Change 8 — `vibe-ai/src/routes.py` (abort graceful fix)

### The problem
When vibe-aiserver restarts (e.g., after a rebuild), it loses its in-memory
`running_tasks` dict. If the backend then calls `POST /jobs/{jobId}/abort`
to reset a stuck job, vibe-ai returned:

```
HTTP 404 — No running task found for job {jobId}
```

The backend's `abortTask` checks `response.status !== 200` and throws an error.
The DB status never gets updated to `ABORTED`, so the teacher's "Rerun" button
stays disabled and the job is permanently stuck.

### The fix
Changed the abort endpoint to return `200` when no task is running:

```python
# BEFORE:
if jobId not in running_tasks:
    raise HTTPException(status_code=404, detail=f"No running task found for job {jobId}")

task = running_tasks[jobId]
if task.done():
    del running_tasks[jobId]
    raise HTTPException(status_code=400, detail=f"Task for job {jobId} has already completed")

# AFTER:
if jobId not in running_tasks:
    # Container may have restarted — return 200 so the backend can still
    # mark the job ABORTED in MongoDB and allow a retry.
    return JobResponse(message=f"No running task for job {jobId} (already stopped)", jobId=jobId)

task = running_tasks[jobId]
if task.done():
    del running_tasks[jobId]
    return JobResponse(message=f"Task for job {jobId} was already completed", jobId=jobId)
```

---

## Infrastructure Change — `docker-compose.yml` (MinIO service replaces fake-gcs)

### Why object storage is needed
vibe-ai uploads and downloads all intermediate files (audio WAV, transcript JSON, question JSON)
via an object storage service. The original code used Google Cloud Storage — which requires a
billing-enabled GCP account.

### Why MinIO
MinIO is an open-source, S3-compatible object store used in production by universities and
enterprises. No cloud account or credit card required. It runs in a single Docker container and
stores files on the server's local disk.

```yaml
minio:
  image: minio/minio:latest
  container_name: vibe-minio
  volumes:
    - ./minio-data:/data
  environment:
    MINIO_ROOT_USER: vibeadmin
    MINIO_ROOT_PASSWORD: change-this-strong-password
  command: server /data --console-address ":9001"
  # Ports intentionally NOT exposed — access via Docker network only
  restart: unless-stopped
  networks:
    - vibe-network
```

Port 9000 (API) and 9001 (web UI) are not exposed publicly. The AI server accesses MinIO
via the internal Docker network. The browser accesses files through the Nginx `/gcs/` proxy.

**MinIO web UI access** (SSH tunnel from your machine):
```bash
ssh -L 9001:localhost:9001 user@your-server
# Open http://localhost:9001 in browser
```

The bucket `vibe-aiserver-data` is **auto-created with public-read policy** on first AI server
startup — no manual setup needed.

---

## New Files Created

| File | Why created |
|------|-------------|
| `vibe-ai/Dockerfile` | vibe-ai had no Dockerfile — required to build the container |
| `vibe-ai/.env` | Container configuration — not committed in original repo |
| `vibe/litellm_config.yaml` | LiteLLM routing config for local LLM |
| `vibe/backend/.dockerignore` | Prevents broken pnpm workspace symlinks from entering Docker |

### `vibe-ai/Dockerfile` (created — was not in original repo)

```dockerfile
FROM python:3.12-slim

RUN apt-get update && apt-get install -y \
    ffmpeg \
    git \
    gcc \
    g++ \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
# tbb has no ARM64 wheel (Apple Silicon); install if available (x86), skip if not
RUN pip install --no-cache-dir tbb 2>/dev/null || true && \
    grep -v '^tbb' requirements.txt > /tmp/requirements_notbb.txt && \
    pip install --no-cache-dir -r /tmp/requirements_notbb.txt

COPY . .

EXPOSE 9017

ENV PYTHONPATH=/app/src
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "9017"]
```

**Why each part was needed:**

| Line | Why |
|------|-----|
| `gcc`, `g++`, `python3-dev` | `hdbscan` (BERTopic dependency) compiles from C source — needs build tools |
| `tbb` workaround | `tbb` has no ARM64 wheel on Apple Silicon. Installs on x86, skipped gracefully on ARM |
| `PYTHONPATH=/app/src` | `src/main.py` uses flat imports like `from routes import router` — Python needs to know where to look |

---

## Why the Backend is Built from Source

Because `WebhookService.ts` (Change 1) was changed, the pre-built DockerHub image
(`vicharanashala/vibe-backend:staging`) still has the old hardcoded IP.
The backend must be compiled from local source.

`docker-compose.yml` was updated from:
```yaml
backend:
  image: vicharanashala/vibe-backend:staging   # pulled from DockerHub
```
to:
```yaml
backend:
  build:
    context: ./backend     # compiled from local source
    dockerfile: Dockerfile
```

---

## Change 9 — `vibe-ai/src/services/question_generation.py` (one-at-a-time generation)

### The problem
The `generate_questions` method generated all N questions in a single LLM call wrapped
in a `{"questions": [...]}` envelope. For `SOL=10` (10 SELECT_ONE_IN_LOT questions), the
output JSON requires approximately 4000–5000 tokens — more than the `max_tokens=4096`
limit. This caused the response to be cut off mid-JSON:

```
Error generating SOL questions for segment 142.4:
  Unterminated string starting at: line 193 column 9 (char 7857)
```

All questions were silently skipped (exception caught), producing an empty `[]` result.

### The fix
Instead of one call with count=N, loop N times each requesting count=1:

```python
# BEFORE (one call for all N questions):
schema = self._build_schema(base_schema, count)
prompt_text = self.create_question_prompt(question_type, count, ...)
result = await self._invoke_structured(model, schema, ...)
questions = self._unwrap_questions(result, count)

# AFTER (N calls, one question each):
for i in range(count):
    prompt_text = self.create_question_prompt(question_type, 1, ...)
    result = await self._invoke_structured(model, base_schema, ...)
    # result is a single question dict — no unwrapping needed
    result["segmentId"] = segment_id
    result["questionType"] = question_type
    all_generated_questions.append(json.dumps(result, ensure_ascii=False))
```

Each single-question response is ~350–500 tokens — well within any model's limit.
Progress is logged per-question (`Generated SOL question 1/10 for segment ...`).

---

## Change 10 — `vibe-ai/src/ai.py` (flatten logic bug)

### The problem
`start_question_generation_task` flattened the results with:

```python
questions = [json.loads(q) for q in questions]
questions = [i for s in questions for i in s]   # ← iterates over dict keys!
```

When each element `s` is a Python dict (single-question case), `for i in s`
yields the dict's KEYS (`"question"`, `"solution"`, `"segmentId"`, `"questionType"`)
instead of the question objects. This produced garbage or was silently wrong.

### The fix
Remove the broken flatten. With one-at-a-time generation, each element is already
a flat question dict — no flattening needed:

```python
# BEFORE:
questions = [json.loads(q) for q in questions]
questions = [i for s in questions for i in s]   # broken for dict elements

# AFTER:
questions = [json.loads(q) for q in questions]  # each element is a question dict
```

---

## Change 11 — `vibe-ai/Dockerfile` (unbuffered Python output)

### The problem
Without `PYTHONUNBUFFERED=1`, Python buffers stdout until the buffer fills.
Background thread print statements (logging question generation progress, errors)
never appeared in `docker logs vibe-aiserver` — making debugging impossible.

The symptoms: "Starting question generation task" appeared (FastAPI thread, flushed
by uvicorn's logging), but no subsequent output from the background thread.

### The fix
```dockerfile
# ADDED:
ENV PYTHONUNBUFFERED=1
```

All `print()` calls now flush immediately to Docker's log stream.

---

## Change 12 — `vibe-ai/src/services/storage.py` (cleanup after generation)

### What was added
New method `delete_job_files(job_id)` retained from prior version, now implemented with the
MinIO SDK. See Change 15 for the full storage.py rewrite details.

Called in `start_question_generation_task` after successful question upload.
Audio `.wav` files (50–500 MB each) and transcript `.json` files are intermediate
artifacts — only the final `questions/*.json` is needed after this stage.

---

## Change 16 — `backend/src/shared/database/providers/mongo/repositories/InviteRepository.ts` (invite E11000 fix)

### The problem
Sending a course invite from the teacher dashboard always failed with a 500 error
after the very first invite was created. The backend log showed only:

```
Message: Failed to create invite
```

The real MongoDB error was silently swallowed by a bare `catch` block in
`InviteRepository.create`. After patching the catch to log the actual error:

```
MongoServerError: E11000 duplicate key error collection: vibe.invites
  index: token_unique dup key: { token: null }
```

**Root cause:** The `invites` MongoDB collection has a unique index named
`token_unique` on the `token` field. This index was created **without** `sparse: true`.
The Invite class never sets a `token` on individual (SINGLE type) invites — so every
invite document has `token: undefined` (stored as `null` in MongoDB). A non-sparse
unique index treats all `null` values as identical — so only **one** invite could
ever exist in the collection. Every subsequent insert hit the duplicate key error.

### The fix — two parts

**Part 1 — one-time MongoDB migration** (already applied to the live database):

```javascript
await db.collection('invites').dropIndex('token_unique');
await db.collection('invites').createIndex(
  { token: 1 },
  { unique: true, sparse: true, name: 'token_unique' }
);
```

`sparse: true` means the index skips documents where `token` is missing or null.
Only BULK invites (shareable link type) generate an actual token value and
those are the only ones that need uniqueness enforced.

**Part 2 — `InviteRepository.ts` source patch** (ensures the sparse index is
re-created correctly on every future rebuild):

```typescript
// In init():
// token_unique must be sparse so invites without a token (all SINGLE invites)
// don't conflict with each other on null.
this.inviteCollection.createIndex(
  {token: 1},
  {unique: true, sparse: true, name: 'token_unique'},
);
```

This replaces the original code which had no `token_unique` `createIndex` call at all
— meaning there was no way to enforce the correct index properties after a rebuild.

### Why the original bug existed
The `token_unique` index was created early in the project when invite links used
tokens for URL routing. The code later switched to using `_id` for routing, but the
index was never updated. The Invite class never set `token` for single invites, and
the stale index blocked all inserts after the first one.

---

## Everything Else — Configuration Only (Not Source Code)

| File | What changed |
|------|-------------|
| `docker-compose.yml` | Backend builds from source; vibe-aiserver added; litellm added; MinIO added — open-source object storage, no cloud account |
| `backend.env` | Firebase credentials; AI_SERVER_IP/PORT; LLM option A/B |
| `frontend/.env` | VITE_BASE_URL, VITE_IS_RECAPTCHA_ENABLED |
| `frontend/nginx.conf` | Added /api proxy block |
| `frontend/Dockerfile` | Added NODE_OPTIONS=--max-old-space-size=8192 |
| `firebase-service-account.json` | Created from backend.env credentials |
| `litellm_config.yaml` | Created for LM Studio routing |
| `vibe-ai/.env` | Replaced GCS vars with MinIO vars | MinIO replaces GCS emulator |

---

## Change 13 — `backend/src/modules/genAI/services/GenAIService.ts` (browser "Load failed" fix)

### The problem
The AI server stored file URLs as `http://minio:9000/vibe-aiserver-data/...` (internal Docker
hostname). When the frontend fetched job task data from the backend and tried to load the
transcript or question files directly, the browser got a network error — `minio` is not
a hostname the browser can resolve outside Docker.

In the teacher dashboard this appeared as **"Load failed"** on the transcript preview, the
segmentation preview, and the question list.

### The fix
Added a URL rewrite helper in `GenAIService.getTaskStatus()` that replaces the internal
hostname prefix with an externally accessible path before returning data to the frontend:

```typescript
const GCS_INTERNAL_URL = process.env.GCS_INTERNAL_URL || '';
const GCS_EXTERNAL_URL = process.env.GCS_EXTERNAL_URL || '';

function rewriteGCSUrl(url?: string): string | undefined {
  if (!url || !GCS_INTERNAL_URL || !GCS_EXTERNAL_URL) return url;
  return url.startsWith(GCS_INTERNAL_URL)
    ? GCS_EXTERNAL_URL + url.slice(GCS_INTERNAL_URL.length)
    : url;
}
```

Applied in `getTaskStatus` before returning:
```typescript
result = result.map((item: any) => {
  const out = { ...item };
  if (out.fileUrl) out.fileUrl = rewriteGCSUrl(out.fileUrl);
  if (out.transcriptFileUrl) out.transcriptFileUrl = rewriteGCSUrl(out.transcriptFileUrl);
  return out;
});
```

**`backend.env` additions:**
```env
GCS_INTERNAL_URL=http://minio:9000
GCS_EXTERNAL_URL=/gcs
```

MongoDB still stores the internal URL. The AI server still receives internal URLs for its
pipeline downloads. Only the API response to the frontend is rewritten.

---

## Change 14 — `frontend/nginx.conf` (MinIO file proxy)

### The problem
The browser needs to download transcript/question files but cannot reach the internal Docker
`minio:9000` hostname. The backend rewrites URLs to `/gcs/...` (Change 13), but Nginx needs
to know where to forward those requests.

### The fix
Added a `/gcs/` location block in `frontend/nginx.conf`:

```nginx
location /gcs/ {
    proxy_pass http://minio:9000/;
    proxy_http_version 1.1;
    proxy_set_header Host minio:9000;
    proxy_read_timeout 60s;
}
```

Browser requests `/gcs/vibe-aiserver-data/transcripts/file.json` → Nginx proxies to
`http://minio:9000/vibe-aiserver-data/transcripts/file.json` → MinIO returns the file.

---

## Change 15 — `vibe-ai/src/services/storage.py` (rewritten for MinIO)

### What changed
The file was completely rewritten to use the `minio` Python SDK instead of `google-cloud-storage`.
The public interface (`upload_file`, `upload_text_content`, `upload_json_content`, `get_file_url`,
`delete_job_files`) is unchanged — all callers in `ai.py` work without modification.

Key differences:
- No GCP credentials needed — only `MINIO_ENDPOINT`, `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY`
- Bucket is auto-created with public-read policy on first init (`_ensure_bucket()`)
- File URLs use `http://minio:9000/bucket/key` format (accessible within Docker network)
- `delete_job_files()` retained — uses `list_objects()` + `remove_object()` from MinIO SDK

**`vibe-ai/requirements.txt`:** `google-cloud-storage>=3.2.0` replaced with `minio>=7.2.0`.

**`vibe-ai/.env`:** Replaced GCS vars with MinIO vars:
```env
# BEFORE:
GCLOUD_PROJECT=vibe-ffa34
GCLOUD_BUCKET_NAME=vibe-aiserver-data
GOOGLE_APPLICATION_CREDENTIALS=/app/firebase-service-account.json
STORAGE_EMULATOR_HOST=http://fake-gcs:4443

# AFTER:
GCLOUD_BUCKET_NAME=vibe-aiserver-data
MINIO_ENDPOINT=minio:9000
MINIO_ACCESS_KEY=vibeadmin
MINIO_SECRET_KEY=change-this-strong-password
MINIO_PUBLIC_URL=http://minio:9000
```
