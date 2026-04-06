#!/usr/bin/env bash
set -euo pipefail

# OmniLux — macOS Install Script
# Installs Node.js 22, pnpm, FFmpeg via Homebrew, builds the project,
# and creates a launchd service for auto-start.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

DEFAULT_PORT=4000
PORT="${PORT:-$DEFAULT_PORT}"
OMNILUX_DATA_DIR="${OMNILUX_DATA_DIR:-$HOME/Library/Application Support/OmniLux}"

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

Install OmniLux on macOS.

Options:
  --port PORT             Server port (default: 4000, env: PORT)
  --data-dir PATH         Data directory (default: ~/Library/Application Support/OmniLux, env: OMNILUX_DATA_DIR)
  --skip-service          Don't create/load the launchd service
  --skip-build            Don't run pnpm install/build (useful for dev)
  --skip-optional         Don't prompt about optional dependencies
  -h, --help              Show this help message

Environment variables:
  PORT                    Server port (default: 4000)
  OMNILUX_DATA_DIR        Data directory path
  OMNILUX_DB_PATH         Database file path (default: <data-dir>/omnilux.db)
  OMNILUX_LIBRARY_ROOT    Media library root path
  OMNILUX_DOWNLOAD_PATH   Download directory path
EOF
  exit 0
}

# ---------------------------------------------------------------------------
# Parse args
# ---------------------------------------------------------------------------
SKIP_SERVICE=false
SKIP_BUILD=false
SKIP_OPTIONAL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)          PORT="$2"; shift 2 ;;
    --data-dir)      OMNILUX_DATA_DIR="$2"; shift 2 ;;
    --skip-service)  SKIP_SERVICE=true; shift ;;
    --skip-build)    SKIP_BUILD=true; shift ;;
    --skip-optional) SKIP_OPTIONAL=true; shift ;;
    -h|--help)       show_help ;;
    *)               die "Unknown option: $1 (use --help for usage)" ;;
  esac
done

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
[[ "$(uname -s)" == "Darwin" ]] || die "This script is for macOS only. Use install-linux.sh for Linux."

step "Installing OmniLux on macOS"
info "Repo root:  $REPO_ROOT"
info "Data dir:   $OMNILUX_DATA_DIR"
info "Port:       $PORT"

# ---------------------------------------------------------------------------
# Homebrew
# ---------------------------------------------------------------------------
step "Checking Homebrew"

if command -v brew &>/dev/null; then
  ok "Homebrew is installed"
else
  info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Add brew to PATH for Apple Silicon
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi

  command -v brew &>/dev/null || die "Homebrew installation failed"
  ok "Homebrew installed"
fi

# ---------------------------------------------------------------------------
# Node.js 22
# ---------------------------------------------------------------------------
step "Checking Node.js 22"

install_node() {
  info "Installing Node.js 22 via Homebrew..."
  brew install node@22
  brew link --overwrite node@22 2>/dev/null || true
}

if command -v node &>/dev/null; then
  NODE_VERSION="$(node --version)"
  NODE_MAJOR="${NODE_VERSION%%.*}"
  NODE_MAJOR="${NODE_MAJOR#v}"
  if [[ "$NODE_MAJOR" -eq 22 ]]; then
    ok "Node.js $NODE_VERSION is installed"
  else
    warn "Node.js $NODE_VERSION found, but Node.js 22.x is required"
    install_node
  fi
else
  install_node
fi

# Verify
node --version | grep -q "^v22\." || die "Node.js 22 is required but $(node --version) is installed"

# ---------------------------------------------------------------------------
# pnpm
# ---------------------------------------------------------------------------
step "Checking pnpm"

if command -v pnpm &>/dev/null; then
  ok "pnpm $(pnpm --version) is installed"
else
  info "Installing pnpm via Homebrew..."
  brew install pnpm
  command -v pnpm &>/dev/null || die "pnpm installation failed"
  ok "pnpm $(pnpm --version) installed"
fi

# ---------------------------------------------------------------------------
# FFmpeg
# ---------------------------------------------------------------------------
step "Checking FFmpeg"

if command -v ffmpeg &>/dev/null; then
  ok "FFmpeg is installed ($(ffmpeg -version 2>&1 | head -1 | awk '{print $3}'))"
else
  info "Installing FFmpeg via Homebrew..."
  brew install ffmpeg
  ok "FFmpeg installed"
fi

# ---------------------------------------------------------------------------
# Optional dependencies
# ---------------------------------------------------------------------------
if [[ "$SKIP_OPTIONAL" == false ]]; then
  step "Optional dependencies"
  info "The following are optional and NOT required for basic operation:"
  info "  - ClamAV (virus scanning): brew install clamav"
  info "  - WireGuard (VPN):         brew install wireguard-tools"
  info "  - Chromium (DDoS solving):  brew install --cask chromium"
  info ""
  info "Skipping optional dependencies. Install manually if needed."
fi

# ---------------------------------------------------------------------------
# Data directories
# ---------------------------------------------------------------------------
step "Creating data directories"

mkdir -p "$OMNILUX_DATA_DIR"
mkdir -p "$OMNILUX_DATA_DIR/downloads"
mkdir -p "$OMNILUX_DATA_DIR/library"
mkdir -p "$OMNILUX_DATA_DIR/logs"
ok "Data directories created at: $OMNILUX_DATA_DIR"

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
if [[ "$SKIP_BUILD" == false ]]; then
  step "Installing dependencies and building"

  cd "$REPO_ROOT"
  info "Running pnpm install..."
  pnpm install --frozen-lockfile 2>/dev/null || pnpm install
  ok "Dependencies installed"

  info "Running pnpm build..."
  pnpm build
  ok "Build complete"
else
  info "Skipping build (--skip-build)"
fi

# ---------------------------------------------------------------------------
# launchd service
# ---------------------------------------------------------------------------
PLIST_LABEL="com.omnilux.server"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"

if [[ "$SKIP_SERVICE" == false ]]; then
  step "Creating launchd service"

  mkdir -p "$HOME/Library/LaunchAgents"

  # Unload existing if present
  if launchctl list "$PLIST_LABEL" &>/dev/null 2>&1; then
    info "Unloading existing service..."
    launchctl bootout "gui/$(id -u)/$PLIST_LABEL" 2>/dev/null || \
      launchctl unload "$PLIST_PATH" 2>/dev/null || true
  fi

  NODE_PATH="$(command -v node)"
  OMNILUX_DB_PATH="${OMNILUX_DB_PATH:-$OMNILUX_DATA_DIR/omnilux.db}"
  OMNILUX_LIBRARY_ROOT="${OMNILUX_LIBRARY_ROOT:-$OMNILUX_DATA_DIR/library}"
  OMNILUX_DOWNLOAD_PATH="${OMNILUX_DOWNLOAD_PATH:-$OMNILUX_DATA_DIR/downloads}"

  cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${PLIST_LABEL}</string>

  <key>ProgramArguments</key>
  <array>
    <string>${NODE_PATH}</string>
    <string>apps/server/dist/index.js</string>
  </array>

  <key>WorkingDirectory</key>
  <string>${REPO_ROOT}</string>

  <key>EnvironmentVariables</key>
  <dict>
    <key>NODE_ENV</key>
    <string>production</string>
    <key>PORT</key>
    <string>${PORT}</string>
    <key>OMNILUX_DB_PATH</key>
    <string>${OMNILUX_DB_PATH}</string>
    <key>OMNILUX_LIBRARY_ROOT</key>
    <string>${OMNILUX_LIBRARY_ROOT}</string>
    <key>OMNILUX_DOWNLOAD_PATH</key>
    <string>${OMNILUX_DOWNLOAD_PATH}</string>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>

  <key>RunAtLoad</key>
  <true/>

  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>

  <key>StandardOutPath</key>
  <string>${OMNILUX_DATA_DIR}/logs/omnilux.log</string>
  <key>StandardErrorPath</key>
  <string>${OMNILUX_DATA_DIR}/logs/omnilux-error.log</string>

  <key>ProcessType</key>
  <string>Background</string>

  <key>SoftResourceLimits</key>
  <dict>
    <key>NumberOfFiles</key>
    <integer>65536</integer>
  </dict>
</dict>
</plist>
PLIST

  ok "Wrote $PLIST_PATH"

  info "Loading service..."
  launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null || \
    launchctl load "$PLIST_PATH" 2>/dev/null || true
  ok "Service loaded"
else
  info "Skipping service creation (--skip-service)"
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

ok "OmniLux installed successfully!"
echo ""
info "Server URL:      http://localhost:$PORT"
info "Data directory:  $OMNILUX_DATA_DIR"
info "Repo root:       $REPO_ROOT"
echo ""
if [[ "$SKIP_SERVICE" == false ]]; then
  info "Service commands:"
  info "  Start:   launchctl kickstart gui/$(id -u)/$PLIST_LABEL"
  info "  Stop:    launchctl kill SIGTERM gui/$(id -u)/$PLIST_LABEL"
  info "  Logs:    tail -f \"$OMNILUX_DATA_DIR/logs/omnilux.log\""
  info "  Unload:  launchctl bootout gui/$(id -u)/$PLIST_LABEL"
else
  info "Manual start:"
  info "  cd $REPO_ROOT && PORT=$PORT node apps/server/dist/index.js"
fi
echo ""
