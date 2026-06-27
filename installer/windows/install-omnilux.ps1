#Requires -Version 5.1

$ErrorActionPreference = "Stop"

$InstallDir = Join-Path $env:LOCALAPPDATA "OmniLux"
$ComposeFile = Join-Path $InstallDir "docker-compose.yml"
$EnvFile = Join-Path $InstallDir ".env"
$DefaultPort = "4000"
$DefaultLibrary = Join-Path $env:USERPROFILE "Media"

function Fail($Message) {
  Write-Error $Message
  exit 1
}

function Require-Command($Name, $InstallHint) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    Fail "$Name is required. $InstallHint"
  }
}

Require-Command "docker" "Install Docker Desktop from https://docs.docker.com/desktop/install/windows-install/"

try {
  docker info *> $null
} catch {
  Fail "Docker Desktop is not running or this user cannot access Docker. Start Docker Desktop and run this installer again."
}

try {
  docker compose version *> $null
} catch {
  Fail "Docker Compose v2 is required. Update Docker Desktop and run this installer again."
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

if (-not (Test-Path $EnvFile)) {
  @"
PORT=$DefaultPort
LIBRARY_ROOT=$DefaultLibrary
OMNILUX_DEPLOYMENT_PROFILE=self-hosted
OMNILUX_PRIMARY_DEPLOYMENT=docker-compose
SUPABASE_URL=https://api.omnilux.tv
SUPABASE_ANON_KEY=
OMNILUX_PUBLIC_ORIGIN=
OMNILUX_CLOUD_APP_URL=https://app.omnilux.tv
OMNILUX_ALLOWED_ORIGINS=
OMNILUX_CLOUD_METADATA_BROKER_TOKEN=
OMNILUX_ENTITLEMENT_LEASE_PUBLIC_KEY_SPKI_B64URL=
OMNILUX_ALLOW_UNSIGNED_ENTITLEMENT_LEASES=false
TMDB_API_KEY=
LOG_LEVEL=info
"@ | Set-Content -Encoding UTF8 $EnvFile
}

@"
services:
  omnilux:
    image: ghcr.io/omnilux-tv/omnilux:latest
    container_name: omnilux
    restart: unless-stopped
    stop_signal: SIGTERM
    stop_grace_period: 90s
    ports:
      - "`${PORT:-4000}:4000"
      - "1900:1900/udp"
    security_opt:
      - no-new-privileges:true
    volumes:
      - omnilux-data:/app/data
      - omnilux-plugins:/app/plugins
      - `${LIBRARY_ROOT:-$DefaultLibrary}:/data
    environment:
      - PORT=4000
      - NODE_ENV=production
      - OMNILUX_DB_PATH=/app/data/omnilux.db
      - OMNILUX_PLUGINS_DIR=/app/plugins
      - OMNILUX_LIBRARY_ROOT=/data
      - OMNILUX_DEPLOYMENT_PROFILE=`${OMNILUX_DEPLOYMENT_PROFILE:-self-hosted}
      - OMNILUX_PRIMARY_DEPLOYMENT=`${OMNILUX_PRIMARY_DEPLOYMENT:-docker-compose}
      - SUPABASE_URL=`${SUPABASE_URL:-https://api.omnilux.tv}
      - SUPABASE_ANON_KEY=`${SUPABASE_ANON_KEY:-}
      - OMNILUX_PUBLIC_ORIGIN=`${OMNILUX_PUBLIC_ORIGIN:-}
      - OMNILUX_CLOUD_APP_URL=`${OMNILUX_CLOUD_APP_URL:-https://app.omnilux.tv}
      - OMNILUX_ALLOWED_ORIGINS=`${OMNILUX_ALLOWED_ORIGINS:-}
      - OMNILUX_CLOUD_METADATA_BROKER_TOKEN=`${OMNILUX_CLOUD_METADATA_BROKER_TOKEN:-}
      - OMNILUX_ENTITLEMENT_LEASE_PUBLIC_KEY_SPKI_B64URL=`${OMNILUX_ENTITLEMENT_LEASE_PUBLIC_KEY_SPKI_B64URL:-}
      - OMNILUX_ALLOW_UNSIGNED_ENTITLEMENT_LEASES=`${OMNILUX_ALLOW_UNSIGNED_ENTITLEMENT_LEASES:-false}
      - TMDB_API_KEY=`${TMDB_API_KEY:-}
      - LOG_LEVEL=`${LOG_LEVEL:-info}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/api/health"]
      interval: 30s
      timeout: 5s
      start_period: 10s
      retries: 3
volumes:
  omnilux-data:
  omnilux-plugins:
"@ | Set-Content -Encoding UTF8 $ComposeFile

docker compose --env-file $EnvFile -f $ComposeFile pull
docker compose --env-file $EnvFile -f $ComposeFile up -d

Write-Host ""
Write-Host "OmniLux is installing and will be available at http://localhost:$DefaultPort"
Write-Host "Configuration directory: $InstallDir"
