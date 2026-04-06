#!/usr/bin/env bash
set -euo pipefail

# OmniLux — Linux Install Script
# Detects distro (apt/dnf/pacman), installs Node.js 22, pnpm, FFmpeg,
# builds the project, and creates a systemd service.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

DEFAULT_PORT=4000
PORT="${PORT:-$DEFAULT_PORT}"
OMNILUX_DATA_DIR="${OMNILUX_DATA_DIR:-/var/lib/omnilux}"
OMNILUX_CONFIG_DIR="/etc/omnilux"

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

Install OmniLux on Linux.

Options:
  --port PORT             Server port (default: 4000, env: PORT)
  --data-dir PATH         Data directory (default: /var/lib/omnilux, env: OMNILUX_DATA_DIR)
  --user USER             System user to run the service as (default: omnilux)
  --skip-service          Don't create/enable the systemd service
  --skip-build            Don't run pnpm install/build
  --skip-optional         Don't show optional dependency info
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
SERVICE_USER="omnilux"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)          PORT="$2"; shift 2 ;;
    --data-dir)      OMNILUX_DATA_DIR="$2"; shift 2 ;;
    --user)          SERVICE_USER="$2"; shift 2 ;;
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
[[ "$(uname -s)" == "Linux" ]] || die "This script is for Linux only."

step "Installing OmniLux on Linux"
info "Repo root:  $REPO_ROOT"
info "Data dir:   $OMNILUX_DATA_DIR"
info "Port:       $PORT"
info "User:       $SERVICE_USER"

# ---------------------------------------------------------------------------
# Detect distro and package manager
# ---------------------------------------------------------------------------
step "Detecting Linux distribution"

PKG_MANAGER=""
DISTRO=""

detect_distro() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    DISTRO="${ID:-unknown}"
  fi

  if command -v apt-get &>/dev/null; then
    PKG_MANAGER="apt"
  elif command -v dnf &>/dev/null; then
    PKG_MANAGER="dnf"
  elif command -v pacman &>/dev/null; then
    PKG_MANAGER="pacman"
  else
    die "No supported package manager found (apt, dnf, pacman)"
  fi
}

detect_distro
ok "Distro: $DISTRO | Package manager: $PKG_MANAGER"

# ---------------------------------------------------------------------------
# Sudo helper
# ---------------------------------------------------------------------------
SUDO=""
if [[ $EUID -ne 0 ]]; then
  if command -v sudo &>/dev/null; then
    SUDO="sudo"
  else
    die "This script requires root privileges. Run as root or install sudo."
  fi
fi

# ---------------------------------------------------------------------------
# Node.js 22
# ---------------------------------------------------------------------------
step "Checking Node.js 22"

install_node_apt() {
  info "Adding NodeSource repository for Node.js 22..."
  $SUDO apt-get update -qq
  $SUDO apt-get install -y -qq ca-certificates curl gnupg

  # NodeSource setup
  $SUDO mkdir -p /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | \
    $SUDO gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg 2>/dev/null || true

  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" | \
    $SUDO tee /etc/apt/sources.list.d/nodesource.list >/dev/null

  $SUDO apt-get update -qq
  $SUDO apt-get install -y -qq nodejs
}

install_node_dnf() {
  info "Adding NodeSource repository for Node.js 22..."
  curl -fsSL https://rpm.nodesource.com/setup_22.x | $SUDO bash -
  $SUDO dnf install -y nodejs
}

install_node_pacman() {
  info "Installing Node.js via pacman..."
  $SUDO pacman -Sy --noconfirm nodejs-lts-jod npm
}

install_node() {
  case "$PKG_MANAGER" in
    apt)    install_node_apt ;;
    dnf)    install_node_dnf ;;
    pacman) install_node_pacman ;;
  esac
}

if command -v node &>/dev/null; then
  NODE_VERSION="$(node --version)"
  NODE_MAJOR="${NODE_VERSION%%.*}"
  NODE_MAJOR="${NODE_MAJOR#v}"
  if [[ "$NODE_MAJOR" -eq 22 ]]; then
    ok "Node.js $NODE_VERSION is installed"
  else
    warn "Node.js $NODE_VERSION found, but 22.x is required"
    install_node
  fi
else
  install_node
fi

node --version | grep -q "^v22\." || die "Node.js 22 is required but $(node --version 2>/dev/null || echo 'none') is installed"
ok "Node.js $(node --version) verified"

# ---------------------------------------------------------------------------
# pnpm
# ---------------------------------------------------------------------------
step "Checking pnpm"

if command -v pnpm &>/dev/null; then
  ok "pnpm $(pnpm --version) is installed"
else
  info "Enabling pnpm via corepack..."
  if command -v corepack &>/dev/null; then
    $SUDO corepack enable
    corepack prepare pnpm@latest --activate 2>/dev/null || true
  else
    info "corepack not found, installing pnpm via npm..."
    $SUDO npm install -g pnpm
  fi
  command -v pnpm &>/dev/null || die "pnpm installation failed"
  ok "pnpm $(pnpm --version) installed"
fi

# ---------------------------------------------------------------------------
# FFmpeg
# ---------------------------------------------------------------------------
step "Checking FFmpeg"

if command -v ffmpeg &>/dev/null; then
  ok "FFmpeg is installed"
else
  info "Installing FFmpeg..."
  case "$PKG_MANAGER" in
    apt)    $SUDO apt-get install -y -qq ffmpeg ;;
    dnf)    $SUDO dnf install -y ffmpeg-free 2>/dev/null || $SUDO dnf install -y ffmpeg ;;
    pacman) $SUDO pacman -S --noconfirm ffmpeg ;;
  esac
  command -v ffmpeg &>/dev/null && ok "FFmpeg installed" || warn "FFmpeg installation failed (optional, streaming/transcoding will be limited)"
fi

# ---------------------------------------------------------------------------
# Build tools (needed for better-sqlite3 native compilation)
# ---------------------------------------------------------------------------
step "Checking build tools"

install_build_tools() {
  case "$PKG_MANAGER" in
    apt)    $SUDO apt-get install -y -qq build-essential python3 ;;
    dnf)    $SUDO dnf groupinstall -y "Development Tools" && $SUDO dnf install -y python3 ;;
    pacman) $SUDO pacman -S --noconfirm base-devel python ;;
  esac
}

if command -v gcc &>/dev/null && command -v make &>/dev/null; then
  ok "Build tools available"
else
  info "Installing build tools (required for native modules)..."
  install_build_tools
  ok "Build tools installed"
fi

# ---------------------------------------------------------------------------
# Optional dependencies
# ---------------------------------------------------------------------------
if [[ "$SKIP_OPTIONAL" == false ]]; then
  step "Optional dependencies"
  info "The following are optional and NOT required for basic operation:"
  case "$PKG_MANAGER" in
    apt)
      info "  - ClamAV:     sudo apt install clamav clamav-daemon"
      info "  - WireGuard:  sudo apt install wireguard-tools"
      info "  - Chromium:   sudo apt install chromium-browser"
      ;;
    dnf)
      info "  - ClamAV:     sudo dnf install clamav clamd"
      info "  - WireGuard:  sudo dnf install wireguard-tools"
      info "  - Chromium:   sudo dnf install chromium"
      ;;
    pacman)
      info "  - ClamAV:     sudo pacman -S clamav"
      info "  - WireGuard:  sudo pacman -S wireguard-tools"
      info "  - Chromium:   sudo pacman -S chromium"
      ;;
  esac
  info ""
  info "Skipping optional dependencies. Install manually if needed."
fi

# ---------------------------------------------------------------------------
# System user
# ---------------------------------------------------------------------------
step "Setting up system user"

if id "$SERVICE_USER" &>/dev/null; then
  ok "User '$SERVICE_USER' exists"
else
  info "Creating system user '$SERVICE_USER'..."
  $SUDO useradd --system --shell /usr/sbin/nologin --home-dir "$OMNILUX_DATA_DIR" --create-home "$SERVICE_USER"
  ok "User '$SERVICE_USER' created"
fi

# ---------------------------------------------------------------------------
# Data directories
# ---------------------------------------------------------------------------
step "Creating data directories"

$SUDO mkdir -p "$OMNILUX_DATA_DIR"
$SUDO mkdir -p "$OMNILUX_DATA_DIR/downloads"
$SUDO mkdir -p "$OMNILUX_DATA_DIR/library"
$SUDO mkdir -p "$OMNILUX_DATA_DIR/logs"
$SUDO mkdir -p "$OMNILUX_CONFIG_DIR"
$SUDO chown -R "$SERVICE_USER:$SERVICE_USER" "$OMNILUX_DATA_DIR"
ok "Data directories created at: $OMNILUX_DATA_DIR"
ok "Config directory: $OMNILUX_CONFIG_DIR"

# ---------------------------------------------------------------------------
# Environment file
# ---------------------------------------------------------------------------
step "Writing environment config"

ENV_FILE="$OMNILUX_CONFIG_DIR/omnilux.env"
OMNILUX_DB_PATH="${OMNILUX_DB_PATH:-$OMNILUX_DATA_DIR/omnilux.db}"
OMNILUX_LIBRARY_ROOT="${OMNILUX_LIBRARY_ROOT:-$OMNILUX_DATA_DIR/library}"
OMNILUX_DOWNLOAD_PATH="${OMNILUX_DOWNLOAD_PATH:-$OMNILUX_DATA_DIR/downloads}"

if [[ -f "$ENV_FILE" ]]; then
  info "Existing $ENV_FILE found -- preserving"
else
  $SUDO tee "$ENV_FILE" >/dev/null <<EOF
NODE_ENV=production
PORT=${PORT}
OMNILUX_DB_PATH=${OMNILUX_DB_PATH}
OMNILUX_LIBRARY_ROOT=${OMNILUX_LIBRARY_ROOT}
OMNILUX_DOWNLOAD_PATH=${OMNILUX_DOWNLOAD_PATH}
EOF
  ok "Wrote $ENV_FILE"
fi

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

  # Ensure service user can read the built files
  $SUDO chown -R "$SERVICE_USER:$SERVICE_USER" "$REPO_ROOT" 2>/dev/null || true
else
  info "Skipping build (--skip-build)"
fi

# ---------------------------------------------------------------------------
# systemd service
# ---------------------------------------------------------------------------
SERVICE_FILE="/etc/systemd/system/omnilux.service"

if [[ "$SKIP_SERVICE" == false ]]; then
  step "Creating systemd service"

  NODE_PATH="$(command -v node)"

  $SUDO tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=OmniLux Media Server
Documentation=https://github.com/omnilux-tv/omnilux
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_USER}
WorkingDirectory=${REPO_ROOT}
ExecStart=${NODE_PATH} apps/server/dist/index.js
EnvironmentFile=${ENV_FILE}
Restart=on-failure
RestartSec=5
StartLimitIntervalSec=60
StartLimitBurst=5

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=${OMNILUX_DATA_DIR}
ReadWritePaths=${REPO_ROOT}/data
PrivateTmp=true

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=omnilux

[Install]
WantedBy=multi-user.target
EOF

  ok "Wrote $SERVICE_FILE"

  info "Reloading systemd..."
  $SUDO systemctl daemon-reload

  info "Enabling omnilux service..."
  $SUDO systemctl enable omnilux.service

  info "Starting omnilux service..."
  $SUDO systemctl start omnilux.service
  ok "Service started"

  # Brief health check
  sleep 2
  if $SUDO systemctl is-active --quiet omnilux.service; then
    ok "Service is running"
  else
    warn "Service may not have started correctly. Check: journalctl -u omnilux -f"
  fi
else
  info "Skipping service creation (--skip-service)"
fi

# ---------------------------------------------------------------------------
# Firewall hint
# ---------------------------------------------------------------------------
if command -v ufw &>/dev/null; then
  info "UFW detected. You may need to allow port $PORT:"
  info "  sudo ufw allow $PORT/tcp"
elif command -v firewall-cmd &>/dev/null; then
  info "firewalld detected. You may need to allow port $PORT:"
  info "  sudo firewall-cmd --permanent --add-port=$PORT/tcp && sudo firewall-cmd --reload"
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
info "Config:          $ENV_FILE"
info "Repo root:       $REPO_ROOT"
echo ""
if [[ "$SKIP_SERVICE" == false ]]; then
  info "Service commands:"
  info "  Status:  sudo systemctl status omnilux"
  info "  Logs:    journalctl -u omnilux -f"
  info "  Stop:    sudo systemctl stop omnilux"
  info "  Restart: sudo systemctl restart omnilux"
else
  info "Manual start:"
  info "  cd $REPO_ROOT && PORT=$PORT node apps/server/dist/index.js"
fi
echo ""
