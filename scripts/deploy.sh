#!/usr/bin/env bash
set -euo pipefail

# Deploy the self-hosted OmniLux server to TrueNAS via Docker Compose
# Usage:
#   ./scripts/deploy.sh [--skip-pull]
#   ./scripts/deploy.sh --local-build [--skip-pull]
#
# Default: pull ghcr.io/omnilux-tv/omnilux and recreate (published image).
# --local-build: rsync the omnilux runtime repo to ./omnilux-src on the NAS and
#   docker compose build there (no GHCR, no CI PAT). For iterative testing.
#   Set OMNILUX_SRC to the omnilux repo root if it is not ../omnilux next to
#   omnilux-deploy (must include omnilux-packages submodule checkout).

REMOTE="truenas"
REMOTE_REPO="${REMOTE_REPO_PATH:-/mnt/Storage/Applications/OmniLux/repo}"
COMPOSE_FILE="${OMNILUX_COMPOSE_FILE:-docker-compose.truenas.yml}"
COMPOSE_LOCAL_BUILD="docker-compose.truenas.local-build.yml"
OMNILUX_IMAGE="${OMNILUX_IMAGE:-ghcr.io/omnilux-tv/omnilux:latest}"
REMOTE_DOCKER="${REMOTE_DOCKER:-sudo -n docker}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OMNILUX_SRC="${OMNILUX_SRC:-$(cd "${DEPLOY_REPO_ROOT}/../omnilux" 2>/dev/null && pwd || true)}"

SKIP_PULL=false
LOCAL_BUILD=false
for arg in "$@"; do
  case "$arg" in
    --skip-build|--skip-pull) SKIP_PULL=true ;;
    --local-build) LOCAL_BUILD=true ;;
  esac
done

if [ "$LOCAL_BUILD" = true ]; then
  OMNILUX_IMAGE="omnilux-truenas-local:latest"
  if [ -z "${OMNILUX_SRC}" ] || [ ! -d "${OMNILUX_SRC}" ]; then
    echo "error: --local-build needs omnilux repo at OMNILUX_SRC or ../omnilux next to omnilux-deploy" >&2
    exit 1
  fi
  if [ ! -d "${OMNILUX_SRC}/omnilux-packages/packages/types" ]; then
    echo "error: ${OMNILUX_SRC}/omnilux-packages missing — run: git submodule update --init --recursive" >&2
    exit 1
  fi
fi

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

if [ "$LOCAL_BUILD" = true ]; then
  echo "==> Syncing omnilux runtime source to ${REMOTE}:${REMOTE_REPO}/omnilux-src ..."
  rsync -az --delete \
    --exclude node_modules \
    --exclude '**/node_modules' \
    --exclude .git \
    --exclude '.env' \
    --exclude '.env.*' \
    --exclude 'apps/server/.output' \
    --exclude 'apps/server/dist' \
    --exclude 'packages/plugin-sdk/dist' \
    --exclude 'omnilux-packages/**/node_modules' \
    --exclude 'omnilux-packages/**/dist' \
    --exclude '.tmp/' \
    --exclude '.worktrees/' \
    "${OMNILUX_SRC}/" "${REMOTE}:${REMOTE_REPO}/omnilux-src/"
  echo "==> Omnilux source sync complete."
fi

if [ "$SKIP_PULL" = false ] && [ "$LOCAL_BUILD" = false ]; then
  echo "==> Pulling image ${OMNILUX_IMAGE}..."
  ssh "${REMOTE}" "cd ${REMOTE_REPO} && OMNILUX_IMAGE='${OMNILUX_IMAGE}' ${REMOTE_DOCKER} compose -f ${COMPOSE_FILE} pull omnilux"
fi

echo "==> Recreating OmniLux server..."
if [ "$LOCAL_BUILD" = true ]; then
  ssh "${REMOTE}" "cd ${REMOTE_REPO} && OMNILUX_IMAGE='${OMNILUX_IMAGE}' ${REMOTE_DOCKER} compose -f ${COMPOSE_FILE} -f ${COMPOSE_LOCAL_BUILD} build omnilux && OMNILUX_IMAGE='${OMNILUX_IMAGE}' ${REMOTE_DOCKER} compose -f ${COMPOSE_FILE} -f ${COMPOSE_LOCAL_BUILD} up -d --build --force-recreate omnilux omnilux-updater"
else
  ssh "${REMOTE}" "cd ${REMOTE_REPO} && OMNILUX_IMAGE='${OMNILUX_IMAGE}' ${REMOTE_DOCKER} compose -f ${COMPOSE_FILE} up -d --build --force-recreate omnilux omnilux-updater"
fi

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
