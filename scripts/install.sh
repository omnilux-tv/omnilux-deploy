#!/usr/bin/env bash
set -euo pipefail

# OmniLux Installer
# curl -fsSL https://omnilux.tv/self-hosted/install.sh | bash

INSTALL_DIR="$HOME/.omnilux"
IMAGE="ghcr.io/omnilux-tv/omnilux:latest"
DEFAULT_PORT=4000
DEFAULT_LIBRARY="$HOME/Media"
CLI_URL="${OMNILUX_CLI_URL:-https://raw.githubusercontent.com/omnilux-tv/omnilux-deploy/main/scripts/omnilux}"
CLI_PATH="${OMNILUX_CLI_PATH:-$HOME/.local/bin/omnilux}"

cat << 'BANNER'

  OmniLux
  Self-hosted media runtime

  Official Docker installer for the OmniLux self-hosted server
BANNER

info()  { printf "\033[1;34m[info]\033[0m  %s\n" "$*"; }
ok()    { printf "\033[1;32m[ok]\033[0m    %s\n" "$*"; }
warn()  { printf "\033[1;33m[warn]\033[0m  %s\n" "$*"; }
die()   { printf "\033[1;31m[error]\033[0m %s\n" "$*" >&2; exit 1; }

detect_os() {
  case "$(uname -s)" in
    Darwin) OS="macos" ;;
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then OS="wsl"
      else OS="linux"; fi ;;
    *) die "Unsupported operating system: $(uname -s)" ;;
  esac
  info "Detected OS: $OS"
}

SUDO=""

check_docker() {
  command -v docker &>/dev/null || die "Docker is not installed. Install it from https://docs.docker.com/get-docker/"

  if [[ "$OS" != "macos" ]] && ! docker info &>/dev/null; then
    if sudo docker info &>/dev/null; then
      SUDO="sudo"
      warn "Docker requires sudo on this system"
    else
      die "Docker daemon is not running or current user lacks permission. Try: sudo systemctl start docker"
    fi
  fi

  $SUDO docker compose version &>/dev/null || die "Docker Compose plugin not found. Install it from https://docs.docker.com/compose/install/"
  ok "Docker and Docker Compose are available"
}

setup_dir() {
  mkdir -p "$INSTALL_DIR"
  info "Install directory: $INSTALL_DIR"
}

write_env() {
  local env_file="$INSTALL_DIR/.env"
  if [[ -f "$env_file" ]]; then
    info "Existing .env found — preserving current values"
    grep -q "^PORT=" "$env_file"         || echo "PORT=$DEFAULT_PORT" >> "$env_file"
    grep -q "^LIBRARY_ROOT=" "$env_file" || echo "LIBRARY_ROOT=$DEFAULT_LIBRARY" >> "$env_file"
  else
    cat > "$env_file" << EOF
# OmniLux configuration
PORT=$DEFAULT_PORT
LIBRARY_ROOT=$DEFAULT_LIBRARY
TMDB_API_KEY=
LOG_LEVEL=info
EOF
    ok "Created .env with defaults"
  fi
}

write_compose() {
  cat > "$INSTALL_DIR/docker-compose.yml" << 'EOF'
services:
  omnilux:
    image: ghcr.io/omnilux-tv/omnilux:latest
    container_name: omnilux
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
    ports:
      - "${PORT:-4000}:4000"
      - "1900:1900/udp"
    security_opt:
      - no-new-privileges:true
    volumes:
      - omnilux-data:/app/data
      - omnilux-plugins:/app/plugins
      - ${LIBRARY_ROOT:-~/Media}:/data
    environment:
      - PORT=4000
      - NODE_ENV=production
      - OMNILUX_DB_PATH=/app/data/omnilux.db
      - OMNILUX_PLUGINS_DIR=/app/plugins
      - OMNILUX_LIBRARY_ROOT=/data
      - TMDB_API_KEY=${TMDB_API_KEY:-}
      - LOG_LEVEL=${LOG_LEVEL:-info}
    deploy:
      resources:
        limits:
          memory: 2G
          cpus: "2.0"
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "5"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/api/health"]
      interval: 30s
      timeout: 5s
      start_period: 10s
      retries: 3
volumes:
  omnilux-data:
  omnilux-plugins:
EOF
  ok "Wrote docker-compose.yml"
}

start_container() {
  info "Pulling latest image..."
  if ! $SUDO docker compose -f "$INSTALL_DIR/docker-compose.yml" --env-file "$INSTALL_DIR/.env" pull; then
    die "Image pull failed. Make sure this host can access the OmniLux runtime image, then run docker login ghcr.io if registry authentication is required. Setup guide: https://github.com/omnilux-tv/omnilux-deploy/blob/main/docs/self-hosted-setup.md"
  fi

  info "Starting OmniLux..."
  $SUDO docker compose -f "$INSTALL_DIR/docker-compose.yml" --env-file "$INSTALL_DIR/.env" up -d
  ok "OmniLux is running"
}

install_cli() {
  local cli_source
  cli_source="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)/omnilux"

  mkdir -p "$(dirname "$CLI_PATH")"
  if [[ -f "$cli_source" ]]; then
    install -m 0755 "$cli_source" "$CLI_PATH"
  else
    curl -fsSL "$CLI_URL" -o "$CLI_PATH"
    chmod 0755 "$CLI_PATH"
  fi

  ok "Installed OmniLux CLI at $CLI_PATH"
  case ":$PATH:" in
    *":$(dirname "$CLI_PATH"):"*) ;;
    *) warn "$(dirname "$CLI_PATH") is not in PATH. Add it to your shell profile to run: omnilux" ;;
  esac
}

main() {
  detect_os
  check_docker
  setup_dir
  write_env
  write_compose
  start_container
  install_cli

  local port
  port=$(grep "^PORT=" "$INSTALL_DIR/.env" | cut -d= -f2)
  port="${port:-$DEFAULT_PORT}"

  echo ""
  ok "OmniLux is ready at http://localhost:$port"
  echo ""
  info "Config directory: $INSTALL_DIR"
  info "To stop:   $SUDO docker compose -f $INSTALL_DIR/docker-compose.yml down"
  info "To update: omnilux update --run"
}

main
