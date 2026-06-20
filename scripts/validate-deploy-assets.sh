#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/env/example.env"

command -v docker >/dev/null 2>&1 || {
  echo "Missing dependency: docker" >&2
  exit 1
}

echo "==> Syntax-checking shell scripts"
bash -n "$ROOT"/scripts/*.sh "$ROOT"/scripts/omnilux "$ROOT"/scripts/install/*.sh

echo "==> Rendering Docker Compose contracts"
docker compose --env-file "$ENV_FILE" -f "$ROOT/docker/docker-compose.yml" config >/dev/null
docker compose --env-file "$ENV_FILE" -f "$ROOT/docker/docker-compose.example.yml" config >/dev/null
docker compose --env-file "$ENV_FILE" -f "$ROOT/docker-compose.truenas.yml" config >/dev/null
docker compose --env-file "$ENV_FILE" -f "$ROOT/docker-compose.truenas.yml" -f "$ROOT/docker-compose.truenas.local-build.yml" config >/dev/null
docker compose --env-file "$ENV_FILE" -f "$ROOT/docker-compose.truenas-ix-image-local.yml" config >/dev/null

echo "==> Checking container hardening defaults"
grep -q "no-new-privileges:true" "$ROOT/docker/docker-compose.yml"
grep -q "no-new-privileges:true" "$ROOT/docker/docker-compose.example.yml"
grep -q "no-new-privileges:true" "$ROOT/docker-compose.truenas.yml"
grep -q "no-new-privileges:true" "$ROOT/scripts/install.sh"

echo "Deploy asset validation passed."
