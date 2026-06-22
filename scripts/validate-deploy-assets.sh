#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/env/example.env"

command -v docker >/dev/null 2>&1 || {
  echo "Missing dependency: docker" >&2
  exit 1
}

command -v node >/dev/null 2>&1 || {
  echo "Missing dependency: node" >&2
  exit 1
}

echo "==> Syntax-checking shell scripts"
bash -n "$ROOT"/scripts/*.sh "$ROOT"/scripts/omnilux "$ROOT"/scripts/install/*.sh

echo "==> Validating structured install contract"
node "$ROOT/scripts/validate-install-contract.mjs"

echo "==> Validating OCI runtime materialization"
node "$ROOT/scripts/validate-oci-materialization.mjs"

echo "==> Validating supervisor control"
node "$ROOT/scripts/validate-supervisor-control.mjs"

echo "==> Validating self-hosted env schema"
node "$ROOT/scripts/validate-self-hosted-env-schema.mjs"

echo "==> Validating deploy profile contract"
node "$ROOT/scripts/validate-deploy-profile-contract.mjs"

echo "==> Validating updater operation"
node "$ROOT/scripts/validate-updater-operation.mjs"

echo "==> Validating install docs projection"
node "$ROOT/scripts/validate-docs-projection.mjs"

echo "==> Rendering Docker Compose contracts"
docker compose --env-file "$ENV_FILE" -f "$ROOT/docker/docker-compose.yml" config >/dev/null
docker compose --env-file "$ENV_FILE" -f "$ROOT/docker/docker-compose.example.yml" config >/dev/null
docker compose --env-file "$ENV_FILE" -f "$ROOT/docker-compose.truenas.yml" config >/dev/null
COMPOSE_PROFILES=updater docker compose --env-file "$ENV_FILE" -f "$ROOT/docker-compose.truenas.yml" config >/dev/null
docker compose --env-file "$ENV_FILE" -f "$ROOT/docker-compose.truenas.yml" -f "$ROOT/docker-compose.truenas.local-build.yml" config >/dev/null
COMPOSE_PROFILES=updater docker compose --env-file "$ENV_FILE" -f "$ROOT/docker-compose.truenas.yml" -f "$ROOT/docker-compose.truenas.local-build.yml" config >/dev/null
docker compose --env-file "$ENV_FILE" -f "$ROOT/docker-compose.truenas-ix-image-local.yml" config >/dev/null

echo "==> Checking container hardening defaults"
grep -q "no-new-privileges:true" "$ROOT/docker/docker-compose.yml"
grep -q "no-new-privileges:true" "$ROOT/docker/docker-compose.example.yml"
grep -q "no-new-privileges:true" "$ROOT/docker-compose.truenas.yml"
grep -q "no-new-privileges:true" "$ROOT/scripts/install.sh"

echo "==> Checking TrueNAS privileged sidecar scope"
if docker compose --env-file "$ENV_FILE" -f "$ROOT/docker-compose.truenas.yml" config --services | grep -qx "omnilux-updater"; then
  echo "omnilux-updater must stay behind the updater profile" >&2
  exit 1
fi
COMPOSE_PROFILES=updater docker compose --env-file "$ENV_FILE" -f "$ROOT/docker-compose.truenas.yml" config --services | grep -qx "omnilux-updater"
COMPOSE_PROFILES=updater docker compose --env-file "$ENV_FILE" -f "$ROOT/docker-compose.truenas.yml" config \
  | grep -q "target: /var/run/docker.sock"

echo "Deploy asset validation passed."
