#!/usr/bin/env bash
set -euo pipefail

# OmniLux Installer
# curl -fsSL https://omnilux.tv/self-hosted/install.sh | bash

INSTALL_DIR="$HOME/.omnilux"
IMAGE="ghcr.io/omnilux-tv/omnilux:latest"
DEFAULT_PORT=4000
DEFAULT_LIBRARY="$HOME/Media"

cat << 'BANNER'

   ██████╗██╗      █████╗ ██╗    ██╗██████╗ ██╗   ██╗███████╗████████╗███████╗██████╗
  ██╔════╝██║     ██╔══██╗██║    ██║██╔══██╗██║   ██║██╔════╝╚══██╔══╝██╔════╝██╔══██╗
  ██║     ██║     ███████║██║ █╗ ██║██████╔╝██║   ██║███████╗   ██║   █████╗  ██████╔╝
  ██║     ██║     ██╔══██║██║███╗██║██╔══██╗██║   ██║╚════██║   ██║   ██╔══╝  ██╔══██╗
  ╚██████╗███████╗██║  ██║╚███╔███╔╝██████╔╝╚██████╔╝███████║   ██║   ███████╗██║  ██║
   ╚═════╝╚══════╝╚═╝  ╚═╝ ╚══╝╚══╝ ╚═════╝  ╚═════╝ ╚══════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝
  All-in-one media automation platform
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
    volumes:
      - omnilux-data:/app/data
      - ${LIBRARY_ROOT:-~/Media}:/data
    environment:
      - PORT=4000
      - NODE_ENV=production
      - OMNILUX_DB_PATH=/app/data/omnilux.db
      - OMNILUX_LIBRARY_ROOT=/data
      - TMDB_API_KEY=${TMDB_API_KEY:-}
      - LOG_LEVEL=${LOG_LEVEL:-info}
    deploy:
      resources:
        limits:
          memory: 2G
          cpus: "2.0"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/api/health"]
      interval: 30s
      timeout: 5s
      start_period: 10s
      retries: 3
volumes:
  omnilux-data:
EOF
  ok "Wrote docker-compose.yml"
}

start_container() {
  info "Pulling latest image..."
  if ! $SUDO docker compose -f "$INSTALL_DIR/docker-compose.yml" --env-file "$INSTALL_DIR/.env" pull; then
    die "Image pull failed (often 'unauthorized' for ghcr.io). Run: echo TOKEN | docker login ghcr.io -u GITHUB_USER --password-stdin (PAT needs read:packages), or use a public ghcr.io/omnilux-tv/omnilux package. Doc: https://github.com/omnilux-tv/omnilux-deploy/blob/main/docs/self-hosted-setup.md"
  fi

  info "Starting OmniLux..."
  $SUDO docker compose -f "$INSTALL_DIR/docker-compose.yml" --env-file "$INSTALL_DIR/.env" up -d
  ok "OmniLux is running"
}

main() {
  detect_os
  check_docker
  setup_dir
  write_env
  write_compose
  start_container

  local port
  port=$(grep "^PORT=" "$INSTALL_DIR/.env" | cut -d= -f2)
  port="${port:-$DEFAULT_PORT}"

  echo ""
  ok "OmniLux is ready at http://localhost:$port"
  echo ""
  info "Config directory: $INSTALL_DIR"
  info "To stop:   $SUDO docker compose -f $INSTALL_DIR/docker-compose.yml down"
  info "To update: re-run this script"
}

main
