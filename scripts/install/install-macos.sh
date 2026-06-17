#!/usr/bin/env bash
set -euo pipefail

# OmniLux bare-metal macOS installer.
#
# This path installs a Darwin-built OmniLux runtime tarball as a user-level
# launchd service. It does not install the Linux container image and does not
# clone the OmniLux source repository.

NODE_MAJOR="${NODE_MAJOR:-22}"
OMNILUX_ARCH="${OMNILUX_ARCH:-}"
OMNILUX_ARTIFACT_URL="${OMNILUX_ARTIFACT_URL:-}"
OMNILUX_ARTIFACT_FILE="${OMNILUX_ARTIFACT_FILE:-}"
OMNILUX_INSTALL_ROOT="${OMNILUX_INSTALL_ROOT:-}"
OMNILUX_SERVICE_LABEL="${OMNILUX_SERVICE_LABEL:-tv.omnilux.server}"
OMNILUX_PORT="${OMNILUX_PORT:-4000}"
OMNILUX_START_SERVICE="${OMNILUX_START_SERVICE:-1}"
OMNILUX_SKIP_DEPENDENCIES="${OMNILUX_SKIP_DEPENDENCIES:-0}"
OMNILUX_SKIP_NODE_SETUP="${OMNILUX_SKIP_NODE_SETUP:-0}"
OMNILUX_SKIP_NODE_CHECK="${OMNILUX_SKIP_NODE_CHECK:-0}"
OMNILUX_PUBLIC_ORIGIN="${OMNILUX_PUBLIC_ORIGIN:-}"
TMDB_API_KEY="${TMDB_API_KEY:-}"

if [[ -n "${OMNILUX_INSTALL_ROOT}" ]]; then
  OMNILUX_APP_DIR="${OMNILUX_APP_DIR:-${OMNILUX_INSTALL_ROOT}/Library/Application Support/OmniLux/runtime}"
  OMNILUX_CONFIG_DIR="${OMNILUX_CONFIG_DIR:-${OMNILUX_INSTALL_ROOT}/Library/Application Support/OmniLux}"
  OMNILUX_DATA_DIR="${OMNILUX_DATA_DIR:-${OMNILUX_INSTALL_ROOT}/Library/Application Support/OmniLux/data}"
  OMNILUX_PLUGINS_DIR="${OMNILUX_PLUGINS_DIR:-${OMNILUX_INSTALL_ROOT}/Library/Application Support/OmniLux/plugins}"
  OMNILUX_MEDIA_DIR="${OMNILUX_MEDIA_DIR:-${OMNILUX_INSTALL_ROOT}/Movies/OmniLux}"
  OMNILUX_LAUNCH_AGENT_DIR="${OMNILUX_LAUNCH_AGENT_DIR:-${OMNILUX_INSTALL_ROOT}/Library/LaunchAgents}"
else
  OMNILUX_APP_DIR="${OMNILUX_APP_DIR:-${HOME}/Library/Application Support/OmniLux/runtime}"
  OMNILUX_CONFIG_DIR="${OMNILUX_CONFIG_DIR:-${HOME}/Library/Application Support/OmniLux}"
  OMNILUX_DATA_DIR="${OMNILUX_DATA_DIR:-${HOME}/Library/Application Support/OmniLux/data}"
  OMNILUX_PLUGINS_DIR="${OMNILUX_PLUGINS_DIR:-${HOME}/Library/Application Support/OmniLux/plugins}"
  OMNILUX_MEDIA_DIR="${OMNILUX_MEDIA_DIR:-${HOME}/Movies/OmniLux}"
  OMNILUX_LAUNCH_AGENT_DIR="${OMNILUX_LAUNCH_AGENT_DIR:-${HOME}/Library/LaunchAgents}"
fi

ENV_FILE="${OMNILUX_CONFIG_DIR}/omnilux.env"
INSTALL_METADATA_FILE="${OMNILUX_CONFIG_DIR}/install.json"
PLIST_FILE="${OMNILUX_LAUNCH_AGENT_DIR}/${OMNILUX_SERVICE_LABEL}.plist"
NODE_BIN="${OMNILUX_NODE_BIN:-}"

info() { printf '\033[1;34m[info]\033[0m  %s\n' "$*"; }
ok() { printf '\033[1;32m[ok]\033[0m    %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m  %s\n' "$*"; }
die() { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
OmniLux bare-metal macOS installer

Usage:
  ./scripts/install/install-macos.sh [install|upgrade|check]

Environment overrides:
  OMNILUX_ARTIFACT_URL=${OMNILUX_ARTIFACT_URL:-auto}
  OMNILUX_ARTIFACT_FILE=              # local .tar.gz artifact, useful for testing
  OMNILUX_INSTALL_ROOT=               # temp prefix for non-system test installs
  OMNILUX_APP_DIR=${OMNILUX_APP_DIR}
  OMNILUX_DATA_DIR=${OMNILUX_DATA_DIR}
  OMNILUX_PLUGINS_DIR=${OMNILUX_PLUGINS_DIR}
  OMNILUX_MEDIA_DIR=${OMNILUX_MEDIA_DIR}
  OMNILUX_PORT=${OMNILUX_PORT}
  OMNILUX_PUBLIC_ORIGIN=${OMNILUX_PUBLIC_ORIGIN:-}
  OMNILUX_NODE_BIN=${NODE_BIN:-auto}
  OMNILUX_SKIP_DEPENDENCIES=1         # skip Homebrew dependency installation
  OMNILUX_SKIP_NODE_SETUP=1           # require an existing Node ${NODE_MAJOR}.x
  OMNILUX_START_SERVICE=0             # install files only, do not start launchd

The installer downloads a Darwin-built OmniLux runtime tarball, installs it
under the current user's Library directory, and manages it as a user launchd
service. Do not run it with sudo.
EOF
}

detect_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || die "This installer only supports macOS."
}

detect_arch() {
  if [[ -n "${OMNILUX_ARCH}" ]]; then
    printf '%s' "${OMNILUX_ARCH}"
    return
  fi

  case "$(uname -m)" in
    arm64|aarch64) printf 'arm64' ;;
    x86_64|amd64) printf 'x64' ;;
    *) die "Unsupported macOS CPU architecture: $(uname -m). Set OMNILUX_ARCH explicitly if an artifact exists." ;;
  esac
}

default_artifact_url() {
  local arch="$1"
  printf 'https://github.com/omnilux-tv/omnilux-deploy/releases/latest/download/omnilux-darwin-%s.tar.gz' "${arch}"
}

node_major() {
  local node_bin="$1"
  "${node_bin}" -p "Number(process.versions.node.split('.')[0])" 2>/dev/null || true
}

find_node_bin() {
  if [[ -n "${NODE_BIN}" ]]; then
    printf '%s' "${NODE_BIN}"
    return
  fi

  if command -v node >/dev/null 2>&1; then
    printf '%s' "$(command -v node)"
    return
  fi

  if command -v brew >/dev/null 2>&1; then
    local node_prefix
    node_prefix="$(brew --prefix node@${NODE_MAJOR} 2>/dev/null || true)"
    if [[ -x "${node_prefix}/bin/node" ]]; then
      printf '%s' "${node_prefix}/bin/node"
      return
    fi
  fi

  printf ''
}

ensure_node() {
  if [[ "${OMNILUX_SKIP_NODE_CHECK}" == "1" ]]; then
    NODE_BIN="$(find_node_bin)"
    [[ -n "${NODE_BIN}" ]] || die "OMNILUX_SKIP_NODE_CHECK=1 still requires OMNILUX_NODE_BIN or node in PATH."
    warn "Skipping Node major-version check because OMNILUX_SKIP_NODE_CHECK=1"
    return
  fi

  NODE_BIN="$(find_node_bin)"
  if [[ -n "${NODE_BIN}" && "$(node_major "${NODE_BIN}")" == "${NODE_MAJOR}" ]]; then
    ok "Node ${NODE_MAJOR}.x is ready at ${NODE_BIN}"
    return
  fi

  if [[ "${OMNILUX_SKIP_NODE_SETUP}" == "1" ]]; then
    die "Node ${NODE_MAJOR}.x is required. Set OMNILUX_NODE_BIN to a Node ${NODE_MAJOR}.x binary."
  fi

  command -v brew >/dev/null 2>&1 || die "Homebrew is required to install Node ${NODE_MAJOR}.x automatically. Install Node ${NODE_MAJOR}.x or set OMNILUX_SKIP_NODE_SETUP=1 with OMNILUX_NODE_BIN."

  info "Installing Node ${NODE_MAJOR}.x with Homebrew..."
  brew install "node@${NODE_MAJOR}"
  NODE_BIN="$(brew --prefix "node@${NODE_MAJOR}")/bin/node"
  [[ "$(node_major "${NODE_BIN}")" == "${NODE_MAJOR}" ]] || die "Node ${NODE_MAJOR}.x is required, found: $("${NODE_BIN}" --version 2>/dev/null || echo missing)"
  ok "Node ${NODE_MAJOR}.x is ready at ${NODE_BIN}"
}

ensure_dependencies() {
  if [[ "${OMNILUX_SKIP_DEPENDENCIES}" == "1" ]]; then
    warn "Skipping Homebrew dependency installation because OMNILUX_SKIP_DEPENDENCIES=1"
    return
  fi

  command -v ffmpeg >/dev/null 2>&1 && {
    ok "ffmpeg is already installed"
    return
  }

  command -v brew >/dev/null 2>&1 || die "Homebrew is required to install ffmpeg automatically. Install ffmpeg or set OMNILUX_SKIP_DEPENDENCIES=1."
  info "Installing ffmpeg with Homebrew..."
  brew install ffmpeg
}

ensure_dirs() {
  install -d -m 0755 "${OMNILUX_APP_DIR%/*}"
  install -d -m 0755 "${OMNILUX_CONFIG_DIR}"
  install -d -m 0755 "${OMNILUX_DATA_DIR}"
  install -d -m 0755 "${OMNILUX_DATA_DIR}/downloads"
  install -d -m 0755 "${OMNILUX_DATA_DIR}/logs"
  install -d -m 0755 "${OMNILUX_PLUGINS_DIR}"
  install -d -m 0755 "${OMNILUX_MEDIA_DIR}"
  install -d -m 0755 "${OMNILUX_LAUNCH_AGENT_DIR}"
  ok "macOS directories are ready"
}

download_or_copy_artifact() {
  local output_file="$1"
  local arch="$2"
  local artifact_url="${OMNILUX_ARTIFACT_URL:-$(default_artifact_url "${arch}")}"

  if [[ -n "${OMNILUX_ARTIFACT_FILE}" ]]; then
    [[ -f "${OMNILUX_ARTIFACT_FILE}" ]] || die "OMNILUX_ARTIFACT_FILE does not exist: ${OMNILUX_ARTIFACT_FILE}"
    cp "${OMNILUX_ARTIFACT_FILE}" "${output_file}"
    printf '%s' "file://${OMNILUX_ARTIFACT_FILE}"
    return
  fi

  info "Downloading ${artifact_url}..." >&2
  curl -fsSL "${artifact_url}" -o "${output_file}"
  printf '%s' "${artifact_url}"
}

entrypoint_relative_path() {
  local app_dir="$1"

  if [[ -f "${app_dir}/apps/server/dist/server/src/backend/index.js" ]]; then
    printf '%s' 'apps/server/dist/server/src/backend/index.js'
  elif [[ -f "${app_dir}/apps/server/dist/server/index.js" ]]; then
    printf '%s' 'apps/server/dist/server/index.js'
  elif [[ -f "${app_dir}/apps/server/.output/server/index.mjs" ]]; then
    printf '%s' 'apps/server/.output/server/index.mjs'
  else
    return 1
  fi
}

materialize_esm_symlinks() {
  local app_dir="$1"
  local entrypoint
  entrypoint="$(entrypoint_relative_path "${app_dir}")" || die "No supported OmniLux server entrypoint found in ${app_dir}"

  case "${entrypoint}" in
    apps/server/dist/server/*)
      find "${app_dir}/apps/server/dist/server" -type f -name '*.js' -exec sh -c '
        for file do
          target="${file%.js}"
          if [ ! -e "$target" ]; then
            ln -s "$(basename "$file")" "$target"
          fi
        done
      ' sh {} +
      ;;
  esac
}

find_extracted_app_dir() {
  local extract_dir="$1"

  if [[ -d "${extract_dir}/app" ]]; then
    printf '%s' "${extract_dir}/app"
  elif [[ -d "${extract_dir}/runtime/app" ]]; then
    printf '%s' "${extract_dir}/runtime/app"
  elif entrypoint_relative_path "${extract_dir}" >/dev/null 2>&1; then
    printf '%s' "${extract_dir}"
  else
    return 1
  fi
}

shell_quote() {
  printf '%q' "$1"
}

write_launcher() {
  local app_dir="$1"
  install -d -m 0755 "${app_dir}/bin"

  cat > "${app_dir}/bin/omnilux-runtime" <<EOF
#!/usr/bin/env bash
set -euo pipefail

APP_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE=$(shell_quote "${ENV_FILE}")
NODE_BIN=$(shell_quote "${NODE_BIN}")

if [[ -f "\${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "\${ENV_FILE}"
  set +a
fi

cd "\${APP_DIR}"

if [[ -f apps/server/dist/server/src/backend/index.js ]]; then
  exec "\${NODE_BIN}" apps/server/dist/server/src/backend/index.js
elif [[ -f apps/server/dist/server/index.js ]]; then
  exec "\${NODE_BIN}" apps/server/dist/server/index.js
elif [[ -f apps/server/.output/server/index.mjs ]]; then
  exec "\${NODE_BIN}" apps/server/.output/server/index.mjs
fi

echo "No supported OmniLux server entrypoint found in \${APP_DIR}" >&2
exit 1
EOF

  chmod 0755 "${app_dir}/bin/omnilux-runtime"
}

install_runtime_artifact() {
  local arch tmp_dir artifact_file extract_dir source_app_dir staging_dir previous_dir timestamp artifact_source
  arch="$(detect_arch)"
  tmp_dir="$(mktemp -d)"
  artifact_file="${tmp_dir}/omnilux-darwin-${arch}.tar.gz"
  extract_dir="${tmp_dir}/extract"
  mkdir -p "${extract_dir}"

  cleanup_tmp() {
    rm -rf "${_OMNILUX_MACOS_TMP_DIR:-}"
  }
  _OMNILUX_MACOS_TMP_DIR="${tmp_dir}"
  trap cleanup_tmp EXIT

  artifact_source="$(download_or_copy_artifact "${artifact_file}" "${arch}")"
  tar -xzf "${artifact_file}" -C "${extract_dir}"
  source_app_dir="$(find_extracted_app_dir "${extract_dir}")" || die "macOS artifact did not contain a supported OmniLux runtime app tree."

  staging_dir="$(mktemp -d "${OMNILUX_APP_DIR}.staging.XXXXXX")"
  cp -a "${source_app_dir}/." "${staging_dir}/"
  materialize_esm_symlinks "${staging_dir}"
  write_launcher "${staging_dir}"

  timestamp="$(date +%Y%m%d%H%M%S)"
  previous_dir="${OMNILUX_APP_DIR}.previous"

  if [[ -e "${OMNILUX_APP_DIR}" ]]; then
    stop_service || true
    rm -rf "${previous_dir}"
    mv "${OMNILUX_APP_DIR}" "${previous_dir}"
  fi
  mv "${staging_dir}" "${OMNILUX_APP_DIR}"

  cat > "${INSTALL_METADATA_FILE}" <<EOF
{
  "artifact": "${artifact_source}",
  "arch": "${arch}",
  "installedAt": "${timestamp}",
  "runtimeDir": "${OMNILUX_APP_DIR}",
  "previousRuntimeDir": "${previous_dir}"
}
EOF
  chmod 0644 "${INSTALL_METADATA_FILE}"

  ok "Installed macOS runtime from ${artifact_source}"
  cleanup_tmp
  unset _OMNILUX_MACOS_TMP_DIR
  trap - EXIT
}

env_line_exists() {
  local key="$1"
  grep -qE "^${key}=" "${ENV_FILE}" 2>/dev/null
}

append_env_default() {
  local key="$1"
  local value="$2"
  if ! env_line_exists "${key}"; then
    printf '%s=%s\n' "${key}" "$(shell_quote "${value}")" >> "${ENV_FILE}"
  fi
}

write_env_file() {
  if [[ ! -f "${ENV_FILE}" ]]; then
    cat > "${ENV_FILE}" <<EOF
# OmniLux bare-metal macOS runtime configuration.
# Edit this file, then run: launchctl kickstart -k gui/\$(id -u)/${OMNILUX_SERVICE_LABEL}
EOF
  fi

  append_env_default "NODE_ENV" "production"
  append_env_default "PORT" "${OMNILUX_PORT}"
  append_env_default "OMNILUX_DEPLOYMENT_PROFILE" "self-hosted"
  append_env_default "OMNILUX_PRIMARY_DEPLOYMENT" "bare-metal-macos"
  append_env_default "OMNILUX_DATA_DIR" "${OMNILUX_DATA_DIR}"
  append_env_default "OMNILUX_DB_PATH" "${OMNILUX_DATA_DIR}/omnilux.db"
  append_env_default "OMNILUX_LIBRARY_ROOT" "${OMNILUX_MEDIA_DIR}"
  append_env_default "OMNILUX_DOWNLOAD_PATH" "${OMNILUX_DATA_DIR}/downloads"
  append_env_default "OMNILUX_PLUGINS_DIR" "${OMNILUX_PLUGINS_DIR}"
  append_env_default "OMNILUX_CLOUD_URL" "https://api.omnilux.tv"
  append_env_default "OMNILUX_CLOUD_APP_URL" "https://app.omnilux.tv"
  append_env_default "OMNILUX_RELAY_URL" "wss://relay.omnilux.tv/ws/server"
  append_env_default "OMNILUX_PUBLIC_ORIGIN" "${OMNILUX_PUBLIC_ORIGIN}"
  append_env_default "OMNILUX_ALLOWED_ORIGINS" "${OMNILUX_PUBLIC_ORIGIN}"
  append_env_default "OMNILUX_BROWSER_SOLVER" "auto"
  append_env_default "TMDB_API_KEY" "${TMDB_API_KEY}"
  append_env_default "LOG_LEVEL" "info"
  chmod 0644 "${ENV_FILE}"
  ok "Environment file is ready at ${ENV_FILE}"
}

xml_escape() {
  sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g'
}

plist_string() {
  printf '%s' "$1" | xml_escape
}

write_launch_agent() {
  cat > "${PLIST_FILE}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$(plist_string "${OMNILUX_SERVICE_LABEL}")</string>
  <key>ProgramArguments</key>
  <array>
    <string>$(plist_string "${OMNILUX_APP_DIR}/bin/omnilux-runtime")</string>
  </array>
  <key>WorkingDirectory</key>
  <string>$(plist_string "${OMNILUX_APP_DIR}")</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$(plist_string "${OMNILUX_DATA_DIR}/logs/omnilux.out.log")</string>
  <key>StandardErrorPath</key>
  <string>$(plist_string "${OMNILUX_DATA_DIR}/logs/omnilux.err.log")</string>
  <key>ProcessType</key>
  <string>Background</string>
</dict>
</plist>
EOF
  chmod 0644 "${PLIST_FILE}"
  ok "LaunchAgent installed at ${PLIST_FILE}"
}

launchd_domain() {
  printf 'gui/%s' "$(id -u)"
}

stop_service() {
  launchctl bootout "$(launchd_domain)" "${PLIST_FILE}" >/dev/null 2>&1 || true
}

start_and_check_service() {
  if [[ "${OMNILUX_START_SERVICE}" != "1" ]]; then
    warn "Skipping service start because OMNILUX_START_SERVICE=${OMNILUX_START_SERVICE}"
    return
  fi

  if [[ -n "${OMNILUX_INSTALL_ROOT}" ]]; then
    die "Refusing to start launchd service when OMNILUX_INSTALL_ROOT is set. Unset it for a real user install."
  fi

  info "Starting ${OMNILUX_SERVICE_LABEL} with launchd..."
  stop_service
  launchctl bootstrap "$(launchd_domain)" "${PLIST_FILE}"
  launchctl enable "$(launchd_domain)/${OMNILUX_SERVICE_LABEL}" >/dev/null 2>&1 || true
  launchctl kickstart -k "$(launchd_domain)/${OMNILUX_SERVICE_LABEL}" >/dev/null 2>&1 || true

  local health_url="http://127.0.0.1:${OMNILUX_PORT}/api/health"
  for _ in $(seq 1 30); do
    if curl -fsS "${health_url}" >/dev/null 2>&1; then
      ok "OmniLux is healthy at ${health_url}"
      return
    fi
    sleep 2
  done

  warn "Service did not pass health check within 60 seconds."
  warn "Recent stderr log:"
  tail -80 "${OMNILUX_DATA_DIR}/logs/omnilux.err.log" 2>/dev/null || true
  exit 1
}

check_installation() {
  detect_macos
  test -x "${OMNILUX_APP_DIR}/bin/omnilux-runtime" || die "Runtime launcher missing at ${OMNILUX_APP_DIR}/bin/omnilux-runtime"
  test -f "${ENV_FILE}" || die "Environment file missing at ${ENV_FILE}"
  test -f "${PLIST_FILE}" || die "LaunchAgent missing at ${PLIST_FILE}"

  if [[ "${OMNILUX_START_SERVICE}" == "1" && -z "${OMNILUX_INSTALL_ROOT}" ]]; then
    launchctl print "$(launchd_domain)/${OMNILUX_SERVICE_LABEL}" >/dev/null
    curl -fsS "http://127.0.0.1:${OMNILUX_PORT}/api/health" >/dev/null
  fi

  ok "Bare-metal macOS installation checks passed"
}

install_or_upgrade() {
  detect_macos
  if [[ "${EUID}" -eq 0 && "${OMNILUX_ALLOW_ROOT:-0}" != "1" ]]; then
    die "Do not run the macOS installer with sudo. It installs a user LaunchAgent."
  fi
  ensure_node
  ensure_dependencies
  ensure_dirs
  install_runtime_artifact
  write_env_file
  write_launch_agent
  start_and_check_service
}

main() {
  local command="${1:-install}"
  case "${command}" in
    -h|--help|help)
      usage
      ;;
    install|upgrade)
      install_or_upgrade
      ;;
    check)
      check_installation
      ;;
    *)
      usage
      die "Unknown command: ${command}"
      ;;
  esac
}

main "$@"
