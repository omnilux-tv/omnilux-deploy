#!/usr/bin/env bash
set -euo pipefail

# Deploy OmniLux to a remote server via SSH + Docker Compose
#
# Setup:
#   1. Copy this file:  cp scripts/deploy.example.sh scripts/deploy.sh
#   2. Edit REMOTE and REMOTE_REPO below to match your server
#   3. Make executable:  chmod +x scripts/deploy.sh
#
# Usage: ./scripts/deploy.sh [--skip-build]
#
# Examples:
#   ./scripts/deploy.sh              # deploy the main server
#   ./scripts/deploy.sh --skip-build # restart without rebuilding

# --- Configure these for your environment ---
REMOTE="${OMNILUX_DEPLOY_HOST:-your-server-ssh-alias}"
REMOTE_REPO="${OMNILUX_DEPLOY_PATH:-/path/to/omnilux/repo}"
COMPOSE_FILE="${OMNILUX_COMPOSE_FILE:-docker-compose.yml}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PRODUCT_REPO="${OMNILUX_PRODUCT_REPO:-${DEPLOY_REPO_ROOT}/../omnilux}"
# ---------------------------------------------

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

if [ "$SKIP_BUILD" = true ]; then
  echo "==> Restarting omnilux (skip build)..."
  ssh "${REMOTE}" "cd ${REMOTE_REPO} && \
    docker compose -f ${COMPOSE_FILE} down omnilux && \
    docker compose -f ${COMPOSE_FILE} up -d omnilux"
else
  echo "==> Rebuilding and restarting omnilux..."
  ssh "${REMOTE}" "cd ${REMOTE_REPO} && \
    docker compose -f ${COMPOSE_FILE} down omnilux && \
    docker compose -f ${COMPOSE_FILE} build --no-cache omnilux && \
    docker compose -f ${COMPOSE_FILE} up -d omnilux"
fi

HEALTH_CONTAINER="omnilux"
echo "==> Waiting for health check (${HEALTH_CONTAINER})..."
for i in $(seq 1 30); do
  if ssh "${REMOTE}" "docker inspect --format='{{.State.Health.Status}}' ${HEALTH_CONTAINER} 2>/dev/null" | grep -q healthy; then
    echo "==> Deployed successfully! ${HEALTH_CONTAINER} is healthy."
    exit 0
  fi
  sleep 2
done

echo "==> WARNING: ${HEALTH_CONTAINER} did not become healthy within 60s. Check logs:"
echo "    ssh ${REMOTE} 'docker compose -f ${REMOTE_REPO}/${COMPOSE_FILE} logs --tail 50 omnilux'"
exit 1
