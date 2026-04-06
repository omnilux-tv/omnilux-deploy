#!/usr/bin/env bash
set -euo pipefail

# OmniLux — Universal Post-Clone Setup
# Assumes Node.js 22 and pnpm are already installed.
# Installs dependencies, builds, initializes the database, and prints next steps.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

DEFAULT_PORT=4000
PORT="${PORT:-$DEFAULT_PORT}"

# Data dir defaults vary by OS
case "$(uname -s)" in
  Darwin) DEFAULT_DATA_DIR="$HOME/Library/Application Support/OmniLux" ;;
  *)      DEFAULT_DATA_DIR="${HOME}/.omnilux" ;;
esac
OMNILUX_DATA_DIR="${OMNILUX_DATA_DIR:-$DEFAULT_DATA_DIR}"

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

info()  { printf "${BLUE}[info]${RESET}  %s\n" "$*"; }
ok()    { printf "${GREEN}[ok]${RESET}    %s\n" "$*"; }
warn()  { printf "${YELLOW}[warn]${RESET}  %s\n" "$*"; }
die()   { printf "${RED}[error]${RESET} %s\n" "$*" >&2; exit 1; }
step()  { printf "\n${BOLD}==> %s${RESET}\n" "$*"; }

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
show_help() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Post-clone setup for OmniLux. Assumes Node.js 22 and pnpm are installed.

Options:
  --port PORT          Server port (default: 4000, env: PORT)
  --data-dir PATH      Data directory (env: OMNILUX_DATA_DIR)
  --skip-build         Only install deps, don't build
  --dev                Install dev dependencies and skip production optimizations
  -h, --help           Show this help message

Environment variables:
  PORT                 Server port (default: 4000)
  OMNILUX_DATA_DIR     Data directory path
  OMNILUX_DB_PATH      Database file path
  OMNILUX_LIBRARY_ROOT Media library root path
  OMNILUX_DOWNLOAD_PATH Download directory path
EOF
  exit 0
}

# ---------------------------------------------------------------------------
# Parse args
# ---------------------------------------------------------------------------
SKIP_BUILD=false
DEV_MODE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)      PORT="$2"; shift 2 ;;
    --data-dir)  OMNILUX_DATA_DIR="$2"; shift 2 ;;
    --skip-build) SKIP_BUILD=true; shift ;;
    --dev)       DEV_MODE=true; shift ;;
    -h|--help)   show_help ;;
    *)           die "Unknown option: $1 (use --help for usage)" ;;
  esac
done

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
step "Preflight checks"

# Node.js 22
if ! command -v node &>/dev/null; then
  die "Node.js is not installed. Install Node.js 22 first."
fi

NODE_VERSION="$(node --version)"
NODE_MAJOR="${NODE_VERSION%%.*}"
NODE_MAJOR="${NODE_MAJOR#v}"
if [[ "$NODE_MAJOR" -ne 22 ]]; then
  die "Node.js 22 is required but $NODE_VERSION is installed."
fi
ok "Node.js $NODE_VERSION"

# pnpm
if ! command -v pnpm &>/dev/null; then
  die "pnpm is not installed. Install via: corepack enable && corepack prepare pnpm@latest --activate"
fi
ok "pnpm $(pnpm --version)"

# Repo root check
if [[ ! -f "$REPO_ROOT/package.json" ]]; then
  die "Cannot find package.json at $REPO_ROOT. Run this script from the repo."
fi
ok "Repo root: $REPO_ROOT"

# Optional: FFmpeg
if command -v ffmpeg &>/dev/null; then
  ok "FFmpeg available (media streaming/transcoding enabled)"
else
  warn "FFmpeg not found. Media streaming and transcoding will be limited."
  warn "Install FFmpeg for full functionality."
fi

# ---------------------------------------------------------------------------
# Data directories
# ---------------------------------------------------------------------------
step "Creating data directories"

mkdir -p "$OMNILUX_DATA_DIR"
mkdir -p "$OMNILUX_DATA_DIR/downloads"
mkdir -p "$OMNILUX_DATA_DIR/library"
mkdir -p "$OMNILUX_DATA_DIR/logs"

# Also ensure repo-local data dir exists (used by dev mode)
mkdir -p "$REPO_ROOT/data"

ok "Data directory: $OMNILUX_DATA_DIR"

# ---------------------------------------------------------------------------
# Install dependencies
# ---------------------------------------------------------------------------
step "Installing dependencies"

cd "$REPO_ROOT"

if [[ "$DEV_MODE" == true ]]; then
  info "Running pnpm install (dev mode)..."
  pnpm install
else
  info "Running pnpm install..."
  pnpm install --frozen-lockfile 2>/dev/null || pnpm install
fi
ok "Dependencies installed"

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
if [[ "$SKIP_BUILD" == false ]]; then
  step "Building project"

  info "Running pnpm build..."
  pnpm build
  ok "Build complete"
else
  info "Skipping build (--skip-build)"
fi

# ---------------------------------------------------------------------------
# Initialize database
# ---------------------------------------------------------------------------
step "Initializing database"

OMNILUX_DB_PATH="${OMNILUX_DB_PATH:-$OMNILUX_DATA_DIR/omnilux.db}"
OMNILUX_LIBRARY_ROOT="${OMNILUX_LIBRARY_ROOT:-$OMNILUX_DATA_DIR/library}"
OMNILUX_DOWNLOAD_PATH="${OMNILUX_DOWNLOAD_PATH:-$OMNILUX_DATA_DIR/downloads}"

# The server runs migrations automatically on startup. Do a quick dry-run
# to initialize the DB schema by starting the server briefly.
if [[ -f "$REPO_ROOT/apps/server/dist/index.js" ]]; then
  info "Running initial startup to apply database migrations..."

  export PORT OMNILUX_DB_PATH OMNILUX_LIBRARY_ROOT OMNILUX_DOWNLOAD_PATH
  export NODE_ENV="production"

  # Start the server, wait for it to initialize, then stop it
  node "$REPO_ROOT/apps/server/dist/index.js" &
  SERVER_PID=$!

  # Wait up to 15s for the server to start and run migrations
  WAITED=0
  while [[ $WAITED -lt 15 ]]; do
    if curl -sf "http://localhost:$PORT/api/health" &>/dev/null; then
      ok "Database initialized (migrations applied)"
      break
    fi
    sleep 1
    WAITED=$((WAITED + 1))

    # Check if server is still running
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
      # Server exited -- might have initialized and exited, or failed
      if [[ -f "$OMNILUX_DB_PATH" ]]; then
        ok "Database file created"
      else
        warn "Server exited before database could be verified"
      fi
      break
    fi
  done

  # Stop the server
  kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
else
  warn "Server not built yet -- database will be initialized on first start"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
printf "${GREEN}${BOLD}"
cat <<'BANNER'
  ___                  _ _
 / _ \ _ __ ___  _ __ (_) |   _   ___  __
| | | | '_ ` _ \| '_ \| | |  | | | \ \/ /
| |_| | | | | | | | | | | |__| |_| |>  <
 \___/|_| |_| |_|_| |_|_|_____\__,_/_/\_\
BANNER
printf "${RESET}\n"

ok "Setup complete!"
echo ""
info "Data directory:  $OMNILUX_DATA_DIR"
info "Database:        $OMNILUX_DB_PATH"
info "Repo root:       $REPO_ROOT"
echo ""
step "Next steps"
echo ""
if [[ "$DEV_MODE" == true ]]; then
  info "Start development server:"
  info "  cd $REPO_ROOT && pnpm dev"
  echo ""
  info "The dev server runs at:"
  info "  Backend:  http://localhost:$PORT"
  info "  Frontend: http://localhost:5173 (Vite proxy -> backend)"
else
  info "Start the server:"
  info "  cd $REPO_ROOT && PORT=$PORT node apps/server/dist/index.js"
  echo ""
  info "Or use the platform-specific install script for auto-start:"
  info "  macOS:   ./scripts/install/install-macos.sh"
  info "  Linux:   ./scripts/install/install-linux.sh"
  info "  Windows: .\\scripts\\install\\install-windows.ps1"
fi
echo ""
info "Server will be available at: http://localhost:$PORT"
echo ""
