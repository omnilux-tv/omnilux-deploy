#!/usr/bin/env bash
set -euo pipefail

# Deploy OmniLux to a remote server via SSH + Docker Compose
#
# Setup:
#   1. Copy this file:  cp scripts/deploy.example.sh scripts/deploy.sh
#   2. Edit REMOTE and REMOTE_REPO below to match your server
#   3. Make executable:  chmod +x scripts/deploy.sh
#
# Usage: ./scripts/deploy.sh [--skip-pull]
#
# Examples:
#   ./scripts/deploy.sh             # deploy the main server
#   ./scripts/deploy.sh --skip-pull # restart without pulling a newer image

# --- Configure these for your environment ---
REMOTE="${OMNILUX_DEPLOY_HOST:-your-server-ssh-alias}"
REMOTE_REPO="${OMNILUX_DEPLOY_PATH:-/path/to/omnilux-deploy}"
COMPOSE_FILE="${OMNILUX_COMPOSE_FILE:-docker-compose.truenas.yml}"
OMNILUX_IMAGE="${OMNILUX_IMAGE:-ghcr.io/omnilux-tv/omnilux:latest}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# ---------------------------------------------

SKIP_PULL=false
for arg in "$@"; do
  case "$arg" in
    --skip-build|--skip-pull) SKIP_PULL=true ;;
  esac
done

echo "==> Syncing to ${REMOTE}:${REMOTE_REPO}..."
rsync -az --delete \
  --exclude node_modules \
  --exclude .git \
  --exclude '.env' \
  --exclude '.env.*' \
  --exclude '.tmp/' \
  --exclude '.worktrees/' \
  "${DEPLOY_REPO_ROOT}/" "${REMOTE}:${REMOTE_REPO}/"

if [ "$SKIP_PULL" = false ]; then
  echo "==> Pulling image ${OMNILUX_IMAGE}..."
  ssh "${REMOTE}" "cd ${REMOTE_REPO} && OMNILUX_IMAGE='${OMNILUX_IMAGE}' docker compose -f ${COMPOSE_FILE} pull omnilux"
fi

echo "==> Restarting omnilux..."
ssh "${REMOTE}" "cd ${REMOTE_REPO} && OMNILUX_IMAGE='${OMNILUX_IMAGE}' docker compose -f ${COMPOSE_FILE} up -d --force-recreate omnilux"

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
