# Local LLM Docker Wrapper — How It Works

This document explains how a local LLM (running in LM Studio on your machine)
is connected to the ViBe application through Docker containers — without changing
any original application source code.

---

## The Problem This Solves

ViBe uses the **Anthropic Claude API** in two places:

| Feature | Where | Original target |
|---------|-------|----------------|
| Quiz / MCQ generation from transcripts | `backend/src/modules/quizzes/services/QuestionService.ts` | Anthropic Cloud API |
| Question generation inside vibe-ai pipeline | `vibe-ai/src/services/question_generation.py` | vLLM server (GPU required) |

Both require either:
- A paid Anthropic API key, or
- A GPU server running vLLM

This document shows how to replace both with **LM Studio running locally on your Mac** — free, private, and no GPU required for smaller models.

---

## Overview: What the Docker Wrapper Does

```
Your App Code                Docker Layer              Your Machine
─────────────                ────────────              ────────────

QuestionService.ts           ANTHROPIC_BASE_URL         LM Studio
  new Anthropic({       →    =http://litellm:4000   →  port 1234
    apiKey: "...",           (LiteLLM container)        nvidia/nemotron-3-nano-4b
  })
  messages.create(...)

question_generation.py       VLLM_BASE_URL
  ChatOpenAI(           →    =http://host.docker.    →  LM Studio
    base_url=...,            internal:1234/v1           port 1234
  )
```

The application code calls the same API it always did. The Docker layer intercepts
the request and routes it to LM Studio instead of the cloud.

---

## Container 1: LiteLLM Proxy

### What it is
LiteLLM is an open-source proxy that translates between different LLM API formats.

**Docker Hub image:** `ghcr.io/berriai/litellm:main-latest`

### Why it is needed for the ViBe backend

The ViBe backend (`QuestionService.ts`) uses the **Anthropic SDK**:
```typescript
const anthropic = new Anthropic({ apiKey: ANTHROPIC_CRED });
const response = await anthropic.messages.create({
  model: ANTHROPIC_MODEL,
  ...
});
```

The Anthropic SDK sends requests in **Anthropic message format** to `api.anthropic.com`.

LM Studio speaks **OpenAI format** at `http://localhost:1234/v1`.

These two formats are different. LiteLLM translates between them:

```
Anthropic SDK (backend)
  POST /v1/messages  {"model": "claude-sonnet-4-20250514", ...}
        ↓
  LiteLLM container (port 4000)
  translates Anthropic format → OpenAI format
        ↓
  POST /v1/chat/completions  {"model": "nvidia/nemotron-3-nano-4b", ...}
        ↓
  LM Studio (port 1234)
        ↓
  Response translated back: OpenAI format → Anthropic format
        ↓
  Anthropic SDK receives it as if it came from Anthropic Cloud
```

### How the redirect works (zero code change)

The Anthropic SDK has a built-in feature: it reads `ANTHROPIC_BASE_URL` from
the environment. If set, it sends all requests there instead of `api.anthropic.com`.

```env
# backend.env
ANTHROPIC_BASE_URL=http://litellm:4000
```

That single env var redirects all Anthropic SDK calls to the LiteLLM container.
No code change needed anywhere.

### Configuration files

**`docker-compose.yml` — LiteLLM service:**
```yaml
litellm:
  image: ghcr.io/berriai/litellm:main-latest
  container_name: vibe-litellm
  volumes:
    - ./litellm_config.yaml:/app/config.yaml
  command: ["--config", "/app/config.yaml", "--port", "4000"]
  ports:
    - "4000:4000"
  extra_hosts:
    - "host.docker.internal:host-gateway"   # lets container reach LM Studio on the host
  networks:
    - vibe-network
```

**`litellm_config.yaml` — model routing:**
```yaml
model_list:
  - model_name: claude-sonnet-4-20250514   # what the backend requests
    litellm_params:
      model: openai/nvidia/nemotron-3-nano-4b   # what LM Studio actually runs
      api_base: http://host.docker.internal:1234/v1
      api_key: not-needed
```

The `model_name` must match `ANTHROPIC_MODEL` in `backend.env`.
The `api_base` is LM Studio's URL — `localhost` becomes `host.docker.internal`
inside Docker so the container can reach your Mac.

**`backend.env` — Option B (local LLM):**
```env
ANTHROPIC_MODEL=claude-sonnet-4-20250514
ANTHROPIC_CRED=local-llm-no-key-needed
ANTHROPIC_BASE_URL=http://litellm:4000
```

---

## Container 2: vibe-aiserver

### What it is
The vibe-ai server is a Python/FastAPI application that runs the full video
processing pipeline (audio extraction → Whisper transcription → segmentation →
question generation).

### Why it does NOT need LiteLLM

Unlike the ViBe backend, vibe-ai's question generation already uses the
**OpenAI-compatible format** via LangChain:

```python
# vibe-ai/src/services/question_generation.py
vllm_base_url = os.getenv("VLLM_BASE_URL", "http://localhost:8081/v1")

self.model = ChatOpenAI(
    model=self.DEFAULT_MODEL,
    base_url=vllm_base_url,    # reads from env var
    api_key="EMPTY",
    temperature=0,
)
```

LM Studio speaks the same format. So vibe-ai can point directly to LM Studio
without any translation layer:

```
vibe-ai question_generation.py
  ChatOpenAI(base_url=VLLM_BASE_URL)
        ↓
  VLLM_BASE_URL=http://host.docker.internal:1234/v1
        ↓
  LM Studio (port 1234) — directly, no LiteLLM needed
```

### Configuration

**`vibe-ai/.env`:**
```env
VLLM_BASE_URL=http://host.docker.internal:1234/v1   # LM Studio URL
```

**`docker-compose.yml` — vibe-aiserver service:**
```yaml
vibe-aiserver:
  build:
    context: ./vibe-ai
    dockerfile: Dockerfile
  container_name: vibe-aiserver
  env_file:
    - ./vibe-ai/.env
  volumes:
    - ./firebase-service-account.json:/app/firebase-service-account.json:ro
  ports:
    - "9017:9017"
  extra_hosts:
    - "host.docker.internal:host-gateway"
  networks:
    - vibe-network
```

**`vibe-ai/Dockerfile`** (created — vibe-ai had none):
```dockerfile
FROM python:3.12-slim

RUN apt-get update && apt-get install -y \
    ffmpeg git gcc g++ python3-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
# tbb has no ARM64 wheel (Apple Silicon); install if available, skip if not
RUN pip install --no-cache-dir tbb 2>/dev/null || true && \
    grep -v '^tbb' requirements.txt > /tmp/requirements_notbb.txt && \
    pip install --no-cache-dir -r /tmp/requirements_notbb.txt

COPY . .

EXPOSE 9017

ENV PYTHONPATH=/app/src
ENV PYTHONUNBUFFERED=1
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "9017"]
```

`gcc`/`g++`/`python3-dev` are required because `hdbscan` (BERTopic dependency)
compiles from C source. `PYTHONPATH=/app/src` is required because vibe-ai uses flat
imports (`from routes import router`) that only resolve when Python knows to look in `/app/src`.

---

## The `host.docker.internal` Key Concept

This is the most important networking concept in this setup.

Inside a Docker container, `localhost` means **the container itself** — not your Mac.

`host.docker.internal` is a special DNS name that Docker automatically resolves
to the IP address of the Docker host (your Mac).

```
Container                         Your Mac
─────────                         ────────
http://localhost:1234         →   (the container itself — nothing there)
http://host.docker.internal:1234  →   LM Studio on your Mac ✅
```

This is why:
- `litellm_config.yaml` uses `http://host.docker.internal:1234/v1`
- `vibe-ai/.env` uses `VLLM_BASE_URL=http://host.docker.internal:1234/v1`

And why both the `litellm` and `vibe-aiserver` services have:
```yaml
extra_hosts:
  - "host.docker.internal:host-gateway"
```
This line makes Docker add `host.docker.internal` to the container's `/etc/hosts`
file so the DNS resolution works correctly on Linux hosts (on macOS Docker Desktop
it works automatically, but this line makes it work everywhere).

---

## How LM Studio Works

LM Studio is an application that runs large language models locally on your Mac.

When you click "Start Server":
- It starts an HTTP server at `http://localhost:1234`
- It exposes the **OpenAI-compatible API** at `/v1/chat/completions`
- The currently loaded model responds to all requests regardless of the model name sent

### What "OpenAI-compatible" means
Both OpenAI's API and LM Studio accept this format:
```json
POST /v1/chat/completions
{
  "model": "any-model-name",
  "messages": [{"role": "user", "content": "Your question here"}],
  "temperature": 0
}
```
LM Studio serves whatever model you have loaded, ignoring the `model` field.

### Currently configured
- **Model loaded in LM Studio:** `nvidia/nemotron-3-nano-4b`
- **LM Studio URL:** `http://localhost:1234` (shown in LM Studio's Local Server tab)
- **Docker sees it as:** `http://host.docker.internal:1234`

### Critical: Disable Auto-Unload

LM Studio has an **auto-unload** feature that drops the loaded model after a period
of inactivity. During question generation, there is a gap between each LLM call (one
question at a time). If the gap exceeds LM Studio's idle timeout, the model is unloaded
mid-generation and all remaining questions fail.

**Symptom:** `docker logs vibe-aiserver` shows questions 1–N generating, then:
```
Error generating SOL question N+1/10: Error code: 400 - {'error': {'message': "No models loaded..."}}
```

**Fix — disable auto-unload before starting a job:**
1. Open LM Studio
2. Go to **Settings** (gear icon, bottom-left)
3. Open the **Performance** tab (or **Advanced**)
4. Find **"Automatically unload model after X minutes of inactivity"**
5. Set it to **Never** (or the maximum value)

---

## Switching the Model

To use a different model, only one line changes in `litellm_config.yaml`:

```yaml
# Change this line:
model: openai/nvidia/nemotron-3-nano-4b

# To whatever model you have loaded in LM Studio, for example:
model: openai/qwen/qwen3.5-9b
```

Then restart:
```bash
docker compose restart litellm
```

No other files need changing.

---

## Switching Between Local LLM and Anthropic Cloud

### Switch to Anthropic Cloud (Option A)

In `backend.env`:
```env
# Comment out Option B:
#ANTHROPIC_CRED=local-llm-no-key-needed
#ANTHROPIC_BASE_URL=http://litellm:4000

# Uncomment Option A:
ANTHROPIC_CRED=sk-ant-YOUR_REAL_API_KEY
ANTHROPIC_MODEL=claude-sonnet-4-20250514
```

Then:
```bash
docker compose up -d backend   # recreate to reload env vars
# litellm container can be stopped since it's no longer needed:
docker compose stop litellm
```

### Switch back to Local LLM (Option B)

In `backend.env`:
```env
# Comment out Option A:
#ANTHROPIC_CRED=sk-ant-...

# Uncomment Option B:
ANTHROPIC_CRED=local-llm-no-key-needed
ANTHROPIC_BASE_URL=http://litellm:4000
ANTHROPIC_MODEL=claude-sonnet-4-20250514
```

Then:
```bash
docker compose up -d litellm backend
```

---

## Full Request Flow — Quiz Generation (End to End)

```
1. Teacher clicks "Generate Questions from Transcript"
   Browser → POST /api/quizzes/questions/generate-csv-res
              { text: "00;00;00;00 - 00;00;30;00 transcript content..." }

2. vibe-backend (Node.js container)
   QuestionService.generateQuestionsWithAI(text)
     → reads ANTHROPIC_CRED="local-llm-no-key-needed"
     → reads ANTHROPIC_BASE_URL="http://litellm:4000"
     → new Anthropic({ apiKey: "local-llm-no-key-needed" })
     → anthropic.messages.create({
         model: "claude-sonnet-4-20250514",
         messages: [{ role: "user", content: "Generate MCQs from: ..." }]
       })
     → SDK sends: POST http://litellm:4000/v1/messages

3. vibe-litellm (LiteLLM container, port 4000)
   Receives Anthropic-format request
   Translates to OpenAI format
   → POST http://host.docker.internal:1234/v1/chat/completions
       { model: "nvidia/nemotron-3-nano-4b", messages: [...] }

4. LM Studio (on your Mac, port 1234)
   nvidia/nemotron-3-nano-4b generates questions
   Returns: { choices: [{ message: { content: "MCQ JSON..." } }] }

5. vibe-litellm translates OpenAI response → Anthropic format
   Returns to vibe-backend

6. QuestionService parses the JSON
   Returns: { success: true, response: [{ questions: [...] }] }

7. Teacher's browser receives the generated questions
```

---

## Full Request Flow — Video Pipeline (End to End)

```
1. Teacher uploads video lecture
   Browser → POST /api/genai/jobs  { videoUrl: "...", courseId: "..." }

2. vibe-backend
   GenAIService.startJob()
     → uploads video to MinIO bucket (vibe-aiserver-data)
     → saves job to MongoDB with status: WAITING
     → returns jobId to browser

3. Teacher clicks "Start Processing" on dashboard
   Browser → POST /api/genai/{jobId}/tasks/approve/start

4. vibe-backend
   WebhookService.approveTaskStart(jobId, jobState)
     → reads AI_SERVER_IP=vibe-aiserver, AI_SERVER_PORT=9017
     → builds URL: http://vibe-aiserver:9017
     → POST http://vibe-aiserver:9017/jobs/{jobId}/tasks/approve/start

5. vibe-aiserver (Python container, port 9017)
   Stage 1: Audio Extraction
     → downloads video from MinIO
     → extracts audio with FFmpeg
     → uploads WAV to MinIO
     → webhook → http://vibe-backend:8080/api/genAI/webhook

6. vibe-backend updates job status → notifies browser via SSE
   Teacher sees: "Audio extracted ✓"

7. Teacher approves Stage 2
   → vibe-aiserver runs Whisper → transcript → MinIO → webhook

8. Teacher approves Stage 3
   → vibe-aiserver runs BERTopic segmentation → segments → MinIO → webhook

9. Teacher approves Stage 4
   → vibe-aiserver question_generation.py
     → ChatOpenAI(base_url="http://host.docker.internal:1234/v1")
     → POST http://host.docker.internal:1234/v1/chat/completions
     → LM Studio generates questions
     → results → MinIO → webhook

10. Backend saves questions to MongoDB
    Teacher's dashboard shows all generated questions ready to use
```

---

## Quick Reference — Commands

```bash
# Start everything
docker compose up -d

# Check all containers
docker compose ps

# View LiteLLM logs (quiz generation)
docker logs vibe-litellm --follow

# View vibe-aiserver logs (video pipeline)
docker logs vibe-aiserver --follow

# Test LiteLLM is working
curl -X POST http://localhost:4000/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: not-needed" \
  -H "anthropic-version: 2023-06-01" \
  -d '{"model":"claude-sonnet-4-20250514","max_tokens":50,"messages":[{"role":"user","content":"say hello"}]}'

# Test vibe-aiserver is running
curl http://localhost:9017/health

# Test LM Studio is reachable from inside Docker
docker exec vibe-litellm curl http://host.docker.internal:1234/v1/models

# Change LM Studio model (edit then restart)
nano litellm_config.yaml
docker compose restart litellm
```

---

## Files and Their Roles

| File | Role |
|------|------|
| `litellm_config.yaml` | Tells LiteLLM which LM Studio model to use and where |
| `backend.env` | Tells backend to use LiteLLM (`ANTHROPIC_BASE_URL`) |
| `vibe-ai/.env` | Tells vibe-ai where LM Studio is (`VLLM_BASE_URL`) |
| `docker-compose.yml` | Defines all containers and their network connections |
| `vibe-ai/Dockerfile` | Instructions to build the vibe-ai Python container |
