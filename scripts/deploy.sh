#!/usr/bin/env bash
set -euo pipefail

# Deploy the self-hosted OmniLux server to TrueNAS via Docker Compose
# Usage: ./scripts/deploy.sh [--skip-build]
#
# This deploy path intentionally handles only the `omnilux` service from
# `docker-compose.truenas.yml`. Sidecars, gaming agents, legacy Tailscale
# helpers, and old clawbuster app wrappers are out of scope here.

REMOTE="truenas"
REMOTE_REPO="${REMOTE_REPO_PATH:-/mnt/Storage/Applications/OmniLux/repo}"
COMPOSE_FILE="${OMNILUX_COMPOSE_FILE:-docker-compose.truenas.yml}"
IMAGE_NAME="omnilux:truenas-local"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PRODUCT_REPO="${OMNILUX_PRODUCT_REPO:-${DEPLOY_REPO_ROOT}/../omnilux}"

if [ ! -f "${PRODUCT_REPO}/package.json" ] || [ ! -d "${PRODUCT_REPO}/apps/server" ]; then
  echo "==> ERROR: OMNILUX_PRODUCT_REPO must point at a sibling omnilux product checkout."
  exit 1
fi

SKIP_BUILD=false
for arg in "$@"; do
  case "$arg" in
    --skip-build) SKIP_BUILD=true ;;
  esac
done

echo "==> Syncing to ${REMOTE}:${REMOTE_REPO}..."
rsync -az --delete \
  --exclude node_modules \
  --exclude .git \
  --exclude dist \
  --exclude build \
  --exclude .output \
  --exclude '.env' \
  --exclude '.env.*' \
  --exclude data \
  --exclude .tmp \
  --exclude 'apps/web/test-results' \
  --exclude .DS_Store \
  --exclude '.claude/worktrees' \
  "${PRODUCT_REPO}/" "${REMOTE}:${REMOTE_REPO}/"
rsync -az --delete \
  --exclude node_modules \
  --exclude .git \
  --exclude dist \
  --exclude build \
  --exclude .output \
  --exclude '.env' \
  --exclude '.env.*' \
  --exclude data \
  --exclude .tmp \
  --exclude .DS_Store \
  --exclude '.claude/worktrees' \
  "${DEPLOY_REPO_ROOT}/docker/" "${REMOTE}:${REMOTE_REPO}/docker/"
rsync -az --delete "${DEPLOY_REPO_ROOT}/deploy/" "${REMOTE}:${REMOTE_REPO}/deploy/"
rsync -az --delete \
  --exclude 'check-runtime.mjs' \
  --exclude 'prepare-web-smoke.mjs' \
  --exclude 'start-web-smoke-server.mjs' \
  --exclude 'run-remote-smoke.sh' \
  --exclude 'starter-library/' \
  "${DEPLOY_REPO_ROOT}/scripts/" "${REMOTE}:${REMOTE_REPO}/scripts/"
rsync -az --delete "${DEPLOY_REPO_ROOT}/scripts/install/" "${REMOTE}:${REMOTE_REPO}/scripts/install/"
rsync -az --delete "${DEPLOY_REPO_ROOT}/docker-compose.truenas.yml" "${REMOTE}:${REMOTE_REPO}/docker-compose.truenas.yml"
echo "==> Sync complete."

# rsync excludes build outputs, which means stale remote artifacts can survive
# across deploys. Remove them explicitly so Docker always builds from a clean
# web workspace instead of reusing old SSR/public output hashes.
ssh "${REMOTE}" "rm -rf ${REMOTE_REPO}/apps/web/.output ${REMOTE_REPO}/apps/web/dist" 2>/dev/null || true

if [ "$SKIP_BUILD" = false ]; then
  echo "==> Building Docker image ${IMAGE_NAME}..."
  if ! ssh -o ServerAliveInterval=30 "${REMOTE}" "bash -lc 'set -o pipefail; cd ${REMOTE_REPO} && docker build --progress=plain -t ${IMAGE_NAME} -f docker/Dockerfile.server . 2>&1 | tail -100'"; then
    echo "==> ERROR: Docker build failed! Check output above."
    exit 1
  fi
  echo "==> Build complete."

  # Prune old build cache to prevent bloat (keep 5GB for fast rebuilds)
  echo "==> Pruning build cache..."
  ssh "${REMOTE}" "docker builder prune --keep-storage 5368709120 -f" 2>/dev/null || true
fi

echo "==> Recreating OmniLux server..."
ssh "${REMOTE}" "cd ${REMOTE_REPO} && docker compose -f ${COMPOSE_FILE} up -d --force-recreate omnilux"

echo "==> Waiting for omnilux to be healthy..."
for i in $(seq 1 40); do
  HEALTH=$(ssh "${REMOTE}" "docker inspect --format='{{.State.Health.Status}}' omnilux 2>/dev/null" || echo "missing")
  if [ "$HEALTH" = "healthy" ]; then
    echo "==> Deployed successfully! omnilux is healthy."
    ssh "${REMOTE}" "docker logs omnilux --tail 5" 2>/dev/null || true
    exit 0
  fi
  echo "    Health: ${HEALTH} (attempt ${i}/40)"
  sleep 3
done

echo "==> WARNING: omnilux did not become healthy within 120s."
echo "==> Last logs:"
ssh "${REMOTE}" "docker logs omnilux --tail 20" 2>/dev/null || true
exit 1
