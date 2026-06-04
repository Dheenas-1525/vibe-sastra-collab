#!/bin/bash
# apply-patches.sh
# Applies all deployment fixes to the developer's source code.
# Run this after receiving new code from the developer, before building Docker.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_SRC="$SCRIPT_DIR/backend/src"
VIBE_AI_SRC="$SCRIPT_DIR/../vibe-ai/src"
PATCHES="$SCRIPT_DIR/patches"

echo "============================================"
echo "  ViBe Docker Wrapper — Applying Patches"
echo "============================================"

# ── Backend patches ──────────────────────────────────────────────────────────

echo ""
echo "[1/3] Backend: WebhookService.ts"
echo "      Fix: AI server URL reads from env var (was hardcoded to GCP IP)"
cp "$PATCHES/backend/modules/genAI/services/WebhookService.ts" \
   "$BACKEND_SRC/modules/genAI/services/WebhookService.ts"
echo "      ✓ Applied"

echo ""
echo "[2/3] Backend: GenAIService.ts"
echo "      Fix: Rewrite internal MinIO URLs to /gcs/... for browser access"
cp "$PATCHES/backend/modules/genAI/services/GenAIService.ts" \
   "$BACKEND_SRC/modules/genAI/services/GenAIService.ts"
echo "      ✓ Applied"

echo ""
echo "[3/4] Backend: BaseService.ts"
echo "      Fix: Retry on MongoDB WriteConflict (error 112) — fixes publish failure"
cp "$PATCHES/backend/shared/classes/BaseService.ts" \
   "$BACKEND_SRC/shared/classes/BaseService.ts"
echo "      ✓ Applied"

echo ""
echo "[4/4] Backend: InviteRepository.ts"
echo "      Fix: Drop token_unique index and recreate as sparse — fixes 'Failed to create invite'"
cp "$PATCHES/backend/shared/database/providers/mongo/repositories/InviteRepository.ts" \
   "$BACKEND_SRC/shared/database/providers/mongo/repositories/InviteRepository.ts"
echo "      ✓ Applied"

# ── vibe-ai patches ──────────────────────────────────────────────────────────

echo ""
echo "[5/9] vibe-ai: storage.py"
echo "      Fix: Replaced Google Cloud Storage SDK with MinIO (no GCP account needed)"
cp "$PATCHES/vibe-ai/services/storage.py" \
   "$VIBE_AI_SRC/services/storage.py"
echo "      ✓ Applied"

echo ""
echo "[6/9] vibe-ai: question_generation.py"
echo "      Fix: Replaced broken LangChain APIs, added max_tokens, one question per call"
cp "$PATCHES/vibe-ai/services/question_generation.py" \
   "$VIBE_AI_SRC/services/question_generation.py"
echo "      ✓ Applied"

echo ""
echo "[7/9] vibe-ai: transcription.py"
echo "      Fix: Cap Whisper model to 'small' (large/medium fill disk on local machine)"
cp "$PATCHES/vibe-ai/services/transcription.py" \
   "$VIBE_AI_SRC/services/transcription.py"
echo "      ✓ Applied"

echo ""
echo "[8/9] vibe-ai: routes.py"
echo "      Fix: Abort returns 200 even when container restarted (fixes stuck jobs)"
cp "$PATCHES/vibe-ai/routes.py" \
   "$VIBE_AI_SRC/routes.py"
echo "      ✓ Applied"

echo ""
echo "[9/9] vibe-ai: ai.py + requirements.txt"
echo "      Fix: Remove broken flatten loop; replace google-cloud-storage with minio"
cp "$PATCHES/vibe-ai/ai.py" \
   "$VIBE_AI_SRC/ai.py"
cp "$PATCHES/vibe-ai/requirements.txt" \
   "$SCRIPT_DIR/../vibe-ai/requirements.txt"
echo "      ✓ Applied"

echo ""
echo "============================================"
echo "  All patches applied successfully!"
echo "============================================"
echo ""
echo "Next step — rebuild the Docker containers:"
echo ""
echo "  cd $(basename $SCRIPT_DIR)"
echo "  docker compose build backend vibe-aiserver"
echo "  docker compose up -d"
echo ""
