#!/usr/bin/env bash
set -euo pipefail

# Deploy the self-hosted OmniLux server to TrueNAS
# Usage:
#   ./scripts/deploy.sh [--skip-pull]
#   ./scripts/deploy.sh --local-build [--skip-pull]
#
# If a container named "omnilux" already exists (e.g. TrueNAS Custom App / ix-apps),
# this script reads compose labels and runs docker compose against that project file
# so recreate does not hit "container name already in use" from a second compose project.
#
# --local-build: rsync omnilux (+ submodule) to REMOTE_REPO/omnilux-src, docker build on
# the NAS to omnilux-truenas-local:latest, then recreate (no GHCR / CI PAT).

REMOTE="truenas"
REMOTE_REPO="${REMOTE_REPO_PATH:-/mnt/Storage/Applications/OmniLux/repo}"
COMPOSE_FILE="${OMNILUX_COMPOSE_FILE:-docker-compose.truenas.yml}"
COMPOSE_LOCAL_BUILD="docker-compose.truenas.local-build.yml"
COMPOSE_IX_IMAGE_LOCAL="docker-compose.truenas-ix-image-local.yml"
OMNILUX_IMAGE="${OMNILUX_IMAGE:-ghcr.io/omnilux-tv/omnilux:latest}"
REMOTE_DOCKER="${REMOTE_DOCKER:-sudo -n docker}"
LOCAL_IMAGE_TAG="${LOCAL_IMAGE_TAG:-omnilux-truenas-local:latest}"

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
  OMNILUX_IMAGE="${LOCAL_IMAGE_TAG}"
  if [ -z "${OMNILUX_SRC}" ] || [ ! -d "${OMNILUX_SRC}" ]; then
    echo "error: --local-build needs omnilux repo at OMNILUX_SRC or ../omnilux next to omnilux-deploy" >&2
    exit 1
  fi
  if [ ! -d "${OMNILUX_SRC}/omnilux-packages/packages/types" ]; then
    echo "error: ${OMNILUX_SRC}/omnilux-packages missing — run: git submodule update --init --recursive" >&2
    exit 1
  fi
fi

ssh_q() {
  ssh "${REMOTE}" "$@"
}

docker_inspect_omnilux() {
  local fmt=$1
  local qfmt
  qfmt=$(printf '%q' "$fmt")
  ssh_q "${REMOTE_DOCKER} inspect omnilux 2>/dev/null --format ${qfmt}" || true
}

# Populate IX_COMPOSE_FILE / IX_COMPOSE_PROJECT when ix-apps (or any compose) owns omnilux.
resolve_ix_compose() {
  IX_COMPOSE_FILE=""
  IX_COMPOSE_PROJECT=""
  local raw cf pj
  raw=$(docker_inspect_omnilux '{{index .Config.Labels "com.docker.compose.project.config_files"}}')
  raw=$(echo "${raw}" | tr -d '\r')
  [[ -z "${raw}" || "${raw}" == "<no value>" ]] && return 0
  # Multiple files are comma-separated; use the first (main stack file).
  cf=${raw%%,*}
  cf=$(echo "${cf}" | tr -d '\r')
  pj=$(docker_inspect_omnilux '{{index .Config.Labels "com.docker.compose.project"}}')
  pj=$(echo "${pj}" | tr -d '\r')
  [[ -z "${pj}" || "${pj}" == "<no value>" ]] && return 0
  if ssh_q "test -f '${cf}'"; then
    IX_COMPOSE_FILE="${cf}"
    IX_COMPOSE_PROJECT="${pj}"
    echo "==> Detected existing omnilux stack: project=${IX_COMPOSE_PROJECT}"
    echo "    compose file: ${IX_COMPOSE_FILE}"
  fi
}

compose_base() {
  echo "-f ${COMPOSE_FILE}"
}

compose_local_build_files() {
  echo "-f ${COMPOSE_FILE} -f ${COMPOSE_LOCAL_BUILD}"
}

compose_ix_local_override() {
  echo "-f '${IX_COMPOSE_FILE}' -f '${REMOTE_REPO}/${COMPOSE_IX_IMAGE_LOCAL}' -p '${IX_COMPOSE_PROJECT}'"
}

compose_ix_only() {
  echo "-f '${IX_COMPOSE_FILE}' -p '${IX_COMPOSE_PROJECT}'"
}

# Recreate updater if present in the stack file; otherwise only omnilux.
remote_compose_up_recreate() {
  local compose_inv=$1
  local services
  if ssh_q "cd '${REMOTE_REPO}' && OMNILUX_IMAGE='${OMNILUX_IMAGE}' ${REMOTE_DOCKER} compose ${compose_inv} config --services 2>/dev/null | grep -qx omnilux-updater"; then
    services="omnilux omnilux-updater"
  else
    services="omnilux"
  fi
  ssh_q "cd '${REMOTE_REPO}' && OMNILUX_IMAGE='${OMNILUX_IMAGE}' ${REMOTE_DOCKER} compose ${compose_inv} up -d --build --force-recreate ${services}"
}

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

IX_COMPOSE_FILE=""
IX_COMPOSE_PROJECT=""
resolve_ix_compose

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

  echo "==> Building ${LOCAL_IMAGE_TAG} on ${REMOTE} (context: ${REMOTE_REPO}/omnilux-src)..."
  ssh_q "${REMOTE_DOCKER} build -t '${LOCAL_IMAGE_TAG}' -f '${REMOTE_REPO}/omnilux-src/.github/docker/Dockerfile.server' '${REMOTE_REPO}/omnilux-src'"
fi

if [ "$SKIP_PULL" = false ] && [ "$LOCAL_BUILD" = false ]; then
  echo "==> Pulling image ${OMNILUX_IMAGE}..."
  ssh_q "${REMOTE_DOCKER} pull '${OMNILUX_IMAGE}'"
  if [[ -n "${IX_COMPOSE_FILE}" ]]; then
    ssh_q "cd '${REMOTE_REPO}' && OMNILUX_IMAGE='${OMNILUX_IMAGE}' ${REMOTE_DOCKER} compose $(compose_ix_only) pull omnilux || true"
  else
    ssh_q "cd '${REMOTE_REPO}' && OMNILUX_IMAGE='${OMNILUX_IMAGE}' ${REMOTE_DOCKER} compose $(compose_base) pull omnilux || true"
  fi
fi

echo "==> Recreating OmniLux server..."
if [ "$LOCAL_BUILD" = true ]; then
  if [[ -n "${IX_COMPOSE_FILE}" ]]; then
    remote_compose_up_recreate "$(compose_ix_local_override)"
  else
    remote_compose_up_recreate "$(compose_local_build_files)"
  fi
else
  if [[ -n "${IX_COMPOSE_FILE}" ]]; then
    remote_compose_up_recreate "$(compose_ix_only)"
  else
    remote_compose_up_recreate "$(compose_base)"
  fi
fi

echo "==> Waiting for omnilux to be healthy..."
for i in $(seq 1 40); do
  HEALTH=$(ssh_q "${REMOTE_DOCKER} inspect --format='{{.State.Health.Status}}' omnilux 2>/dev/null" || echo "missing")
  if [ "$HEALTH" = "healthy" ]; then
    echo "==> Deployed successfully! omnilux is healthy."
    echo "==> Deployed image:"
    ssh_q "${REMOTE_DOCKER} inspect --format='image={{.Config.Image}} id={{.Image}} revision={{index .Config.Labels \"org.opencontainers.image.revision\"}} created={{index .Config.Labels \"org.opencontainers.image.created\"}}' omnilux" 2>/dev/null || true
    ssh_q "${REMOTE_DOCKER} logs omnilux --tail 5" 2>/dev/null || true
    exit 0
  fi
  echo "    Health: ${HEALTH} (attempt ${i}/40)"
  sleep 3
done

echo "==> WARNING: omnilux did not become healthy within 120s."
echo "==> Last logs:"
ssh_q "${REMOTE_DOCKER} logs omnilux --tail 20" 2>/dev/null || true
exit 1
