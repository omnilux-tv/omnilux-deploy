#!/usr/bin/env bash
set -euo pipefail

# Deploy the self-hosted OmniLux server to TrueNAS via Docker Compose
# Usage: ./scripts/deploy.sh [--skip-pull]
#
# This deploy path intentionally handles only the `omnilux` service from
# `docker-compose.truenas.yml` using a published container image. Sidecars,
# gaming agents, legacy Tailscale helpers, and old clawbuster app wrappers are
# out of scope here.

REMOTE="truenas"
REMOTE_REPO="${REMOTE_REPO_PATH:-/mnt/Storage/Applications/OmniLux/repo}"
COMPOSE_FILE="${OMNILUX_COMPOSE_FILE:-docker-compose.truenas.yml}"
OMNILUX_IMAGE="${OMNILUX_IMAGE:-ghcr.io/omnilux-tv/omnilux:latest}"
REMOTE_DOCKER="${REMOTE_DOCKER:-sudo -n docker}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

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
echo "==> Sync complete."

if [ "$SKIP_PULL" = false ]; then
  echo "==> Pulling image ${OMNILUX_IMAGE}..."
  ssh "${REMOTE}" "cd ${REMOTE_REPO} && OMNILUX_IMAGE='${OMNILUX_IMAGE}' ${REMOTE_DOCKER} compose -f ${COMPOSE_FILE} pull omnilux"
fi

echo "==> Recreating OmniLux server..."
ssh "${REMOTE}" "cd ${REMOTE_REPO} && OMNILUX_IMAGE='${OMNILUX_IMAGE}' ${REMOTE_DOCKER} compose -f ${COMPOSE_FILE} up -d --build --force-recreate omnilux omnilux-updater"

echo "==> Waiting for omnilux to be healthy..."
for i in $(seq 1 40); do
  HEALTH=$(ssh "${REMOTE}" "${REMOTE_DOCKER} inspect --format='{{.State.Health.Status}}' omnilux 2>/dev/null" || echo "missing")
  if [ "$HEALTH" = "healthy" ]; then
    echo "==> Deployed successfully! omnilux is healthy."
    ssh "${REMOTE}" "${REMOTE_DOCKER} logs omnilux --tail 5" 2>/dev/null || true
    exit 0
  fi
  echo "    Health: ${HEALTH} (attempt ${i}/40)"
  sleep 3
done

echo "==> WARNING: omnilux did not become healthy within 120s."
echo "==> Last logs:"
ssh "${REMOTE}" "${REMOTE_DOCKER} logs omnilux --tail 20" 2>/dev/null || true
exit 1
