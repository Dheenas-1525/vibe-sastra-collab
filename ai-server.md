# ViBe AI Server — Complete Guide

This document explains what the vibe-ai server is, what it does, how it works,
how it connects to ViBe, and how to run it locally. Written so that someone
with no prior knowledge of the system can understand it end-to-end.

---

## What is the vibe-ai Server?

The vibe-ai server is a **separate Python application** that handles all
video and audio processing for ViBe. It is not part of the main ViBe backend
(Node.js). It is its own independent service.

**What it does:**
When a teacher uploads a video lecture, the vibe-ai server automatically:
1. Extracts the audio from the video
2. Converts speech to text (transcription)
3. Splits the transcript into topic-based segments
4. Generates educational questions from each segment

This process is called the **GenAI pipeline**.

---

## Why is it Separate from the Main Backend?

The main ViBe backend (Node.js) handles user authentication, courses, quizzes,
and the database. It is fast and lightweight.

The vibe-ai server handles heavy machine learning work:
- Running Whisper (a speech recognition model)
- Running BERTopic (a topic segmentation model)
- Running an LLM for question generation

These tasks take minutes, not milliseconds. Keeping it separate allows
both to run independently.

---

## The Four-Stage Pipeline

When a teacher starts a GenAI job (submits a YouTube URL or video), the vibe-ai server runs
four stages in sequence. The teacher can see the status and approve each step from the dashboard.

```
Stage 1: Audio Extraction
    Input:  Video URL
    Tool:   yt-dlp (video downloader) + FFmpeg (audio converter)
    Output: 16kHz mono WAV audio file → uploaded to GCS
    Time:   Seconds to minutes (depends on video length)

Stage 2: Transcript Generation
    Input:  WAV audio file from Stage 1
    Tool:   OpenAI Whisper (runs locally — no internet needed after model download)
    Output: Full text transcript with timestamps → uploaded to GCS
    Model:  'small' (~2GB, capped for local deployment)
    Time:   ~1× real-time on CPU (10-min video ≈ 10 minutes)

Stage 3: Segmentation
    Input:  Transcript from Stage 2
    Tool:   BERTopic + SentenceTransformers (all-mpnet-base-v2)
    Output: Transcript split into topic-coherent segments → uploaded to GCS
    Time:   30 seconds – 2 minutes

Stage 4: Question Generation
    Input:  Each segment from Stage 3
    Tool:   LLM via OpenAI-compatible API (LM Studio locally)
    Output: Educational questions (MCQ, True/False, Descriptive, etc.)
    Time:   1–10 minutes (depends on LLM speed and number of segments)
```

---

## How the Backend and vibe-ai Server Talk to Each Other

They communicate in two directions:

### Direction 1: Backend → vibe-ai (commands)

| What the backend sends | vibe-ai endpoint | What it does |
|------------------------|------------------|-------------|
| Approve and start a stage | `POST /jobs/{id}/tasks/approve/start` | Begins the next pipeline stage |
| Approve and move forward | `POST /jobs/{id}/tasks/approve/continue` | Accepts the stage output and starts next |
| Rerun a failed stage | `POST /jobs/{id}/tasks/rerun` | Reruns the current stage |
| Cancel a job | `POST /jobs/{id}/abort` | Stops processing (graceful — returns 200 even if container restarted) |
| Health check | `GET /health` | Confirms vibe-ai is reachable |

### Direction 2: vibe-ai → Backend (progress reports)

After each stage completes, vibe-ai sends a **webhook** back to the main backend:

```
vibe-ai → POST http://vibe-backend:8080/api/genAI/webhook
          Header: X-Webhook-Secret: vibe-local-secret
          Body: { jobId, stage, status, outputUrl }
```

The backend receives this, updates the job status in MongoDB, and notifies the
teacher's browser via Server-Sent Events (SSE) so the dashboard updates in real time.

### Data Transfer (Google Cloud Storage)

Files are too large to send directly between services. Instead:

```
Teacher submits YouTube URL
      ↓
Backend tells vibe-ai: "process this URL"
      ↓
vibe-ai downloads video → extracts audio → uploads WAV to GCS
      ↓
vibe-ai transcribes audio → uploads transcript JSON to GCS
      ↓
vibe-ai segments transcript → uploads segments to GCS
      ↓
vibe-ai generates questions → uploads questions JSON to GCS
      ↓
vibe-ai tells backend: "result is at this GCS URL"
      ↓
Backend reads result from GCS → saves to MongoDB
```

**For self-hosting:** a **MinIO** Docker container provides S3-compatible object
storage. No cloud account or credit card needed. Files are stored at
`vibe/minio-data/` on the server disk.

---

## Environment Variables

All configuration for vibe-ai is in `vibe-ai/.env`:

| Variable | Required | Description |
|----------|----------|-------------|
| `WEBHOOK_SECRET` | Yes | Secret key — both backend and vibe-ai must have the same value. |
| `WEBHOOK_URL` | Yes | URL vibe-ai calls to report progress. `http://vibe-backend:8080/api/genAI/webhook` in Docker. |
| `VLLM_BASE_URL` | Yes | URL of the LLM API. For LM Studio: `http://host.docker.internal:1234/v1`. |
| `GCLOUD_BUCKET_NAME` | Yes | MinIO bucket name. `vibe-aiserver-data` — auto-created on first start. |
| `MINIO_ENDPOINT` | Yes | MinIO server address inside Docker. `minio:9000`. |
| `MINIO_ACCESS_KEY` | Yes | MinIO username. Must match `MINIO_ROOT_USER` in `docker-compose.yml`. |
| `MINIO_SECRET_KEY` | Yes | MinIO password. Must match `MINIO_ROOT_PASSWORD` in `docker-compose.yml`. |
| `MINIO_PUBLIC_URL` | Yes | Internal URL for building file download links. `http://minio:9000`. |
| `PORT` | No | Port to listen on. Default: `9017`. |

---

## Object Storage — MinIO (No Cloud Account Required)

The original vibe-ai was designed to use real Google Cloud Storage. For self-hosting,
we use **MinIO** — an open-source, production-ready object store used by universities
and enterprises worldwide. No GCP account, billing, or credit card needed.

**How it works:**
- MinIO runs as a Docker container on the internal `vibe-network` (ports not exposed publicly)
- The `minio` Python SDK (`storage.py`) uploads/downloads files to/from MinIO
- File URLs use the internal Docker hostname: `http://minio:9000/vibe-aiserver-data/...`
- The backend rewrites these internal URLs to `/gcs/...` before returning them to the browser
- Nginx proxies `/gcs/...` requests to MinIO so the browser can load transcripts and questions
- Files are stored at `vibe/minio-data/` on the server disk
- The bucket `vibe-aiserver-data` is **auto-created with public-read policy** on first start

**MinIO web UI** (browser-based file manager — useful for debugging):
```bash
# Access via SSH tunnel from your laptop:
ssh -L 9001:localhost:9001 user@your-server
# Then open http://localhost:9001  (login: vibeadmin / your-password)
```

---

## LLM for Question Generation

For local self-hosting, question generation uses **LM Studio** running a smaller
model on your machine.

- vibe-ai reads the LLM URL from `VLLM_BASE_URL` env var
- LM Studio exposes an OpenAI-compatible API at `http://localhost:1234/v1`
- Setting `VLLM_BASE_URL=http://host.docker.internal:1234/v1` redirects all
  question generation calls to LM Studio

**Currently configured model:** `nvidia/nemotron-3-nano-4b` in LM Studio

**Important:** Questions are generated **one at a time** (one LLM call per question) to stay
within the model's token budget. Generating 10 questions at once requires ~4000–5000 output
tokens — more than most small models support. Each single question requires only ~400 tokens.
After all questions are generated, the audio and transcript files are automatically deleted
from GCS to free disk space.

---

## Whisper Model Sizes

vibe-ai's Whisper model size is capped to `small` for local deployment.
The `small` model is downloaded on first use (~461MB) and cached inside the container.

| Model | Speed | Accuracy | RAM needed | Local status |
|-------|-------|----------|-----------|-------------|
| `tiny` | Very fast | Lower | ~1 GB | Allowed |
| `base` | Fast | Moderate | ~1 GB | Allowed |
| `small` | Moderate | Good | ~2 GB | **Allowed — default** |
| `medium` | Slow | Better | ~5 GB | Capped → `small` |
| `large` | Very slow | Best | ~10 GB | Capped → `small` (fills disk) |

Even if the UI sends `modelSize: 'large'`, the code maps it to `'small'` to
prevent disk exhaustion on local machines.

---

## Source Code Changes from Original

The original vibe-ai repo had several bugs that prevented it from running:

| File | Change | Reason |
|------|--------|--------|
| `requirements.txt` | Added `langchain-openai`, `langchain-core`; replaced `google-cloud-storage` with `minio` | Missing LangChain packages; GCS SDK replaced by MinIO |
| `src/services/question_generation.py` | Replaced `create_agent`/`ToolStrategy` with `_invoke_structured` | Non-existent LangChain 1.0 APIs — server crashed on startup |
| `src/services/question_generation.py` | Added `max_tokens=4096` to `ChatOpenAI` | LM Studio default (~2048) too small — JSON truncated |
| `src/services/question_generation.py` | Generate one question per call (loop N times) | Batch of 10 questions exceeded token limit — all silently failed |
| `src/ai.py` | Fixed flatten logic (`for i in s` on dict) | Iterating over dict yields keys, not values — wrong result type |
| `src/services/storage.py` | Rewritten for MinIO SDK; retains `delete_job_files()` | GCS replaced by MinIO; cleans up audio/transcript after generation |
| `src/services/transcription.py` | Cap model size to `small` | `large` model (10GB) filled disk, crashing Docker |
| `src/routes.py` | Abort returns 200 when no task running | 404 on restart blocked job retries permanently |
| `Dockerfile` | Added `PYTHONUNBUFFERED=1` | Background thread logs were invisible in Docker |

See `vibe-ai-source-changes.md` for the exact diffs.

---

## How to Run Locally (Docker)

### Prerequisites
- Docker Desktop running
- LM Studio installed with a model loaded and server started at `http://localhost:1234`

### Directory Structure Required
```
vibe-new/
├── vibe/               ← main ViBe repo (docker-compose.yml lives here)
│   ├── docker-compose.yml
│   ├── backend.env
│   ├── firebase-service-account.json
│   └── minio-data/     ← created automatically by MinIO on first start
└── vibe-ai/            ← vibe-ai repo
    ├── Dockerfile
    ├── .env
    └── src/
```

### Step 1 — Start LM Studio
1. Open LM Studio → load your model
2. **Disable auto-unload:** Settings → Performance → set "Auto-unload model after X minutes" to **Never**
   (Without this, the model is dropped mid-generation and questions fail partway through)
3. Go to Local Server tab → click Start Server
4. Confirm: `Server listening on http://localhost:1234`

### Step 2 — Build and Start All Containers
```bash
cd vibe-new/vibe
docker compose build backend vibe-aiserver
docker compose up -d
```

### Step 3 — Verify Everything is Running
```bash
docker compose ps
```

Expected:
```
NAME              STATUS
vibe-backend      Up (healthy)
vibe-frontend     Up
vibe-aiserver     Up
vibe-litellm      Up
vibe-minio        Up
```

```bash
curl http://localhost:9017/health
# Expected: {"status": "healthy"}
```

### Step 4 — Watch the Pipeline Run
```bash
docker logs --follow vibe-aiserver
```

You should see:
```
Model size 'large' capped to 'small' for local deployment
Starting Whisper transcription for: http://minio:9000/... (model: small, language: en)
Segmenting transcript...
Generating questions...
Generated SOL question 1/10 for segment 142.4
Generated SOL question 2/10 for segment 142.4
...
Cleanup: deleted 2 intermediate file(s) for job <jobId>
```

---

## Troubleshooting

### "Transcribing content..." stuck
- Check `docker logs vibe-aiserver` — Whisper `small` model (~461MB) needs to download on first run
- If it was previously stuck on `large` model: run `docker system prune` to clear disk, then retry
- The cap in `transcription.py` prevents re-downloading large models

### Question generation returns error or fails
- Check LM Studio is running (`curl http://localhost:1234/v1/models`)
- Check `VLLM_BASE_URL=http://host.docker.internal:1234/v1` in `vibe-ai/.env`
- If JSON parse error or truncation: already fixed — questions are generated one at a time
- Check `docker logs vibe-aiserver --follow` for per-question progress: `Generated SOL question 1/10...`

### Question generation produces empty results (`[]`)
- Run `docker logs vibe-aiserver --follow` and look for `Error generating SOL question ...` lines
- The container now uses `PYTHONUNBUFFERED=1` — all errors appear immediately in logs
- If no error visible: LM Studio may have timed out — check LM Studio is loaded and responding
- Test directly: `curl http://localhost:1234/v1/models`

### Question generation loops — job keeps restarting / re-triggering
- **Root cause:** LM Studio auto-unloads the model during the gap between question calls.
  All remaining questions fail with `"No models loaded"`, the job completes with 0 questions,
  and the backend re-triggers the job.
- **Fix:** Open LM Studio → Settings → Performance → set **"Auto-unload model after X minutes"**
  to **Never** before starting a job.
- Confirm the model stays loaded: `curl http://localhost:1234/v1/models` should return the model
  name throughout the entire generation run.

### Job stuck after container restart (can't retry)
- The abort endpoint now returns 200 on container restart — click "Abort" in the dashboard, then "Rerun"

### MinIO upload fails / storage unavailable
- Confirm `MINIO_ENDPOINT=minio:9000` in `vibe-ai/.env`
- Confirm `vibe-minio` container is running: `docker compose ps`
- Confirm credentials match: `MINIO_ACCESS_KEY`/`MINIO_SECRET_KEY` must equal `MINIO_ROOT_USER`/`MINIO_ROOT_PASSWORD` in `docker-compose.yml`
- The bucket `vibe-aiserver-data` is auto-created on first run — no manual setup needed

### Webhook not reaching backend
- Confirm `WEBHOOK_URL=http://vibe-backend:8080/api/genAI/webhook` in `vibe-ai/.env`
- Both containers must be on `vibe-network`

---

## API Reference

All endpoints require the `X-Webhook-Secret` header (except `/` and `/health`).

```
GET  /                              Health check — lists all endpoints
GET  /health                        Simple {"status": "healthy"}

POST /jobs/{jobId}/tasks/approve/start     Start the next pipeline stage
POST /jobs/{jobId}/tasks/approve/continue  Accept output and move to next stage
POST /jobs/{jobId}/tasks/rerun             Rerun the current stage
POST /jobs/{jobId}/abort                   Cancel the job (graceful — 200 even after restart)
```

---

## Technology Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Web framework | FastAPI (Python) | Handles HTTP requests |
| Speech-to-text | OpenAI Whisper (`small` model) | Converts audio to transcript |
| Topic modeling | BERTopic + SentenceTransformers | Splits transcript into segments |
| Question generation | LLM via LangChain + LM Studio | Generates educational questions |
| File storage | MinIO (self-hosted, open-source) | Stores intermediate files; bucket auto-created on start |
| Video download | yt-dlp + FFmpeg | Extracts audio from video files |
| Server | Uvicorn (ASGI) | Runs the FastAPI app on port 9017 |
