#!/bin/bash
# update-and-rebuild.sh
# One command to pull latest code from GitHub, apply patches, and rebuild Docker.
#
# Usage:
#   bash update-and-rebuild.sh          # just apply patches + rebuild (no git pull)
#   bash update-and-rebuild.sh --git    # pull latest code from GitHub + patch + rebuild

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Repo URLs ─────────────────────────────────────────────────────────────────
VIBE_MONOREPO_URL="https://github.com/vicharanashala/vibe.git"   # contains backend/
VIBE_AI_URL="https://github.com/vicharanashala/vibe-ai.git"       # standalone vibe-ai

# ── Paths ─────────────────────────────────────────────────────────────────────
BACKEND_DIR="$SCRIPT_DIR/backend"           # vibe/backend/
VIBE_AI_DIR="$SCRIPT_DIR/../vibe-ai"        # vibe-ai/

# ── Log file setup ────────────────────────────────────────────────────────────
LOG_DIR="$SCRIPT_DIR/update-logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="$LOG_DIR/update_$TIMESTAMP.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "============================================"
echo "  ViBe — Update & Rebuild"
echo "  Started: $(date)"
echo "  Log: update-logs/update_$TIMESTAMP.log"
echo "============================================"

# ── Show current versions ─────────────────────────────────────────────────────
echo ""
echo "── Current versions before update ──"
echo "  backend:  $(git -C $BACKEND_DIR log -1 --format='%h %s' 2>/dev/null || echo '(no git history)')"
echo "  vibe-ai:  $(git -C $VIBE_AI_DIR log -1 --format='%h %s' 2>/dev/null || echo '(no git history)')"

# ── Pull from GitHub ──────────────────────────────────────────────────────────
if [ "$1" = "--git" ]; then
  echo ""
  echo "── Pulling latest code from GitHub ──"

  # ── Backend: lives inside vicharanashala/vibe monorepo ──
  echo ""
  echo "  → Updating backend from $VIBE_MONOREPO_URL ..."
  TEMP_MONOREPO="/tmp/vibe-monorepo-update"
  rm -rf "$TEMP_MONOREPO"
  git clone --depth=1 "$VIBE_MONOREPO_URL" "$TEMP_MONOREPO"
  rsync -a --delete --exclude='.git' "$TEMP_MONOREPO/backend/" "$BACKEND_DIR/"
  rm -rf "$TEMP_MONOREPO"
  echo "  ✓ Backend updated from monorepo"

  # ── vibe-ai: standalone repo ──
  echo ""
  echo "  → Updating vibe-ai from $VIBE_AI_URL ..."
  if [ -d "$VIBE_AI_DIR/.git" ]; then
    git -C "$VIBE_AI_DIR" pull
  else
    git clone "$VIBE_AI_URL" "$VIBE_AI_DIR"
  fi
  echo "  ✓ vibe-ai updated"

  echo ""
  echo "── Versions after update ──"
  echo "  backend:  (from vicharanashala/vibe monorepo — $(git -C /tmp 2>/dev/null || echo 'latest'))"
  echo "  vibe-ai:  $(git -C $VIBE_AI_DIR log -1 --format='%h %s' 2>/dev/null)"
fi

# ── Apply deployment patches ──────────────────────────────────────────────────
echo ""
bash "$SCRIPT_DIR/apply-patches.sh"

# ── Docker image state before rebuild ────────────────────────────────────────
echo ""
echo "── Docker image state before rebuild ──"
docker compose -f "$SCRIPT_DIR/docker-compose.yml" images 2>/dev/null || echo "  (no images yet)"

# ── Rebuild Docker containers ─────────────────────────────────────────────────
echo ""
echo "── Building Docker containers ──"
cd "$SCRIPT_DIR"
docker compose build backend vibe-aiserver
echo "  ✓ Build complete"

echo ""
echo "── Restarting containers ──"
docker compose up -d
echo "  ✓ All containers started"

# ── Wait for backend to become healthy ───────────────────────────────────────
echo ""
echo "── Waiting for backend health check ──"
for i in $(seq 1 18); do
  STATUS=$(docker inspect vibe-backend --format='{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
  echo "  Attempt $i/18: $STATUS"
  if [ "$STATUS" = "healthy" ]; then
    break
  fi
  sleep 10
done

# ── Final status ──────────────────────────────────────────────────────────────
echo ""
echo "── Final container status ──"
docker compose ps

echo ""
echo "── Docker image versions after rebuild ──"
docker compose images

echo ""
echo "============================================"
echo "  Update complete!"
echo "  Finished: $(date)"
echo "  Full log: update-logs/update_$TIMESTAMP.log"
echo "  App running at: http://localhost:3000"
echo "============================================"
