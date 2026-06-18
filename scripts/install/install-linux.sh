#!/usr/bin/env bash
set -euo pipefail

# OmniLux bare-metal Linux installer.
#
# This path installs the published OmniLux runtime image as a native systemd
# service without requiring Docker or source repository access.

NODE_MAJOR="${NODE_MAJOR:-22}"

OMNILUX_IMAGE="${OMNILUX_IMAGE:-ghcr.io/omnilux-tv/omnilux:latest}"
OMNILUX_IMAGE_PLATFORM="${OMNILUX_IMAGE_PLATFORM:-}"
OMNILUX_APP_DIR="${OMNILUX_APP_DIR:-/opt/omnilux}"
OMNILUX_CONFIG_DIR="${OMNILUX_CONFIG_DIR:-/etc/omnilux}"
OMNILUX_DATA_DIR="${OMNILUX_DATA_DIR:-/var/lib/omnilux}"
OMNILUX_PLUGINS_DIR="${OMNILUX_PLUGINS_DIR:-/var/lib/omnilux/plugins}"
OMNILUX_MEDIA_DIR="${OMNILUX_MEDIA_DIR:-/srv/media}"
OMNILUX_USER="${OMNILUX_USER:-omnilux}"
OMNILUX_GROUP="${OMNILUX_GROUP:-omnilux}"
OMNILUX_PORT="${OMNILUX_PORT:-4000}"
OMNILUX_SERVICE_NAME="${OMNILUX_SERVICE_NAME:-omnilux}"
OMNILUX_START_SERVICE="${OMNILUX_START_SERVICE:-1}"
OMNILUX_SKIP_DEPENDENCIES="${OMNILUX_SKIP_DEPENDENCIES:-0}"
OMNILUX_SKIP_NODE_SETUP="${OMNILUX_SKIP_NODE_SETUP:-0}"
OMNILUX_PUBLIC_ORIGIN="${OMNILUX_PUBLIC_ORIGIN:-}"
TMDB_API_KEY="${TMDB_API_KEY:-}"

SERVICE_FILE="/etc/systemd/system/${OMNILUX_SERVICE_NAME}.service"
ENV_FILE="${OMNILUX_CONFIG_DIR}/omnilux.env"
INSTALL_METADATA_FILE="${OMNILUX_CONFIG_DIR}/install.json"

info() { printf '\033[1;34m[info]\033[0m  %s\n' "$*"; }
ok() { printf '\033[1;32m[ok]\033[0m    %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m  %s\n' "$*"; }
die() { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
OmniLux bare-metal Linux installer

Usage:
  sudo ./scripts/install/install-linux.sh [install|upgrade|check]

Environment overrides:
  OMNILUX_IMAGE=${OMNILUX_IMAGE}
  OMNILUX_IMAGE_PLATFORM=${OMNILUX_IMAGE_PLATFORM:-linux/amd64}
  OMNILUX_APP_DIR=${OMNILUX_APP_DIR}
  OMNILUX_DATA_DIR=${OMNILUX_DATA_DIR}
  OMNILUX_PLUGINS_DIR=${OMNILUX_PLUGINS_DIR}
  OMNILUX_MEDIA_DIR=${OMNILUX_MEDIA_DIR}
  OMNILUX_PORT=${OMNILUX_PORT}
  OMNILUX_PUBLIC_ORIGIN=${OMNILUX_PUBLIC_ORIGIN:-}
  OMNILUX_SKIP_DEPENDENCIES=1   # skip apt package installation
  OMNILUX_SKIP_NODE_SETUP=1     # require an existing Node ${NODE_MAJOR}.x
  OMNILUX_START_SERVICE=0       # install files only, do not start systemd
  OMNILUX_REGISTRY_USERNAME=github-user
  GHCR_TOKEN=ghp_...            # optional, needed when the runtime image is private

The installer downloads the published OmniLux runtime image from GHCR, extracts
the built /app runtime into ${OMNILUX_APP_DIR}, and runs it as a native systemd
service. No Docker daemon and no OmniLux source repository access are required.
EOF
}

require_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    return
  fi

  if command -v sudo >/dev/null 2>&1; then
    exec sudo -E "$0" "$@"
  fi

  die "Run as root or install sudo."
}

detect_supported_os() {
  if [[ ! -f /etc/os-release ]]; then
    die "Unsupported Linux distribution: /etc/os-release is missing."
  fi

  # shellcheck disable=SC1091
  . /etc/os-release
  local family="${ID:-} ${ID_LIKE:-}"
  case "${family}" in
    *ubuntu*|*debian*)
      ok "Detected supported distribution: ${PRETTY_NAME:-${ID:-Linux}}"
      ;;
    *)
      die "Bare-metal installer currently supports Ubuntu/Debian hosts. Use Docker or install dependencies manually on ${PRETTY_NAME:-this distribution}."
      ;;
  esac

  if ! command -v systemctl >/dev/null 2>&1; then
    die "systemd is required for the bare-metal service path."
  fi
}

detect_platform() {
  if [[ -n "${OMNILUX_IMAGE_PLATFORM}" ]]; then
    printf '%s' "${OMNILUX_IMAGE_PLATFORM}"
    return
  fi

  case "$(uname -m)" in
    x86_64|amd64) printf 'linux/amd64' ;;
    aarch64|arm64) printf 'linux/arm64' ;;
    *) die "Unsupported CPU architecture: $(uname -m). Set OMNILUX_IMAGE_PLATFORM explicitly if an image exists." ;;
  esac
}

ensure_system_packages() {
  if [[ "${OMNILUX_SKIP_DEPENDENCIES}" == "1" ]]; then
    warn "Skipping apt dependency installation because OMNILUX_SKIP_DEPENDENCIES=1"
    return
  fi

  info "Installing system dependencies..."
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    ffmpeg \
    gzip \
    pciutils \
    p7zip-full \
    sqlite3 \
    tar \
    vainfo \
    zstd
}

node_major() {
  node -p "Number(process.versions.node.split('.')[0])" 2>/dev/null || true
}

ensure_node() {
  local current_major
  current_major="$(node_major)"
  if [[ "${current_major}" == "${NODE_MAJOR}" ]]; then
    ok "Node ${NODE_MAJOR}.x is already installed"
    return
  fi

  if [[ "${OMNILUX_SKIP_NODE_SETUP}" == "1" ]]; then
    die "Node ${NODE_MAJOR}.x is required and OMNILUX_SKIP_NODE_SETUP=1 was set."
  fi

  info "Installing Node ${NODE_MAJOR}.x from NodeSource..."
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
  DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs

  current_major="$(node_major)"
  [[ "${current_major}" == "${NODE_MAJOR}" ]] || die "Node ${NODE_MAJOR}.x is required, found: $(node --version 2>/dev/null || echo missing)"
  ok "Node $(node --version) is ready"
}

ensure_user_and_dirs() {
  if ! getent group "${OMNILUX_GROUP}" >/dev/null; then
    groupadd --system "${OMNILUX_GROUP}"
  fi

  if ! id "${OMNILUX_USER}" >/dev/null 2>&1; then
    useradd \
      --system \
      --gid "${OMNILUX_GROUP}" \
      --home-dir "${OMNILUX_DATA_DIR}" \
      --shell /usr/sbin/nologin \
      "${OMNILUX_USER}"
  fi

  install -d -m 0755 -o root -g root "$(dirname "${OMNILUX_APP_DIR}")"
  install -d -m 0750 -o root -g "${OMNILUX_GROUP}" "${OMNILUX_CONFIG_DIR}"
  install -d -m 0750 -o "${OMNILUX_USER}" -g "${OMNILUX_GROUP}" "${OMNILUX_DATA_DIR}"
  install -d -m 0750 -o "${OMNILUX_USER}" -g "${OMNILUX_GROUP}" "${OMNILUX_DATA_DIR}/downloads"
  install -d -m 0750 -o "${OMNILUX_USER}" -g "${OMNILUX_GROUP}" "${OMNILUX_PLUGINS_DIR}"

  if [[ ! -d "${OMNILUX_MEDIA_DIR}" ]]; then
    install -d -m 0755 -o "${OMNILUX_USER}" -g "${OMNILUX_GROUP}" "${OMNILUX_MEDIA_DIR}"
  fi

  ok "Host directories are ready"
}

parse_image_ref() {
  local image="$1"
  if [[ "${image}" != */* ]]; then
    die "OMNILUX_IMAGE must include a registry and repository, for example ghcr.io/omnilux-tv/omnilux:latest"
  fi

  local registry="${image%%/*}"
  local remainder="${image#*/}"
  local repository reference

  if [[ "${remainder}" == *@* ]]; then
    repository="${remainder%@*}"
    reference="${remainder#*@}"
  elif [[ "${remainder##*/}" == *:* ]]; then
    repository="${remainder%:*}"
    reference="${remainder##*:}"
  else
    repository="${remainder}"
    reference="latest"
  fi

  printf '%s\n%s\n%s\n' "${registry}" "${repository}" "${reference}"
}

node_json() {
  node - "$@"
}

registry_token() {
  local registry="$1"
  local repository="$2"
  local token_file token
  local username password

  username="${OMNILUX_REGISTRY_USERNAME:-${GITHUB_ACTOR:-}}"
  password="${OMNILUX_REGISTRY_PASSWORD:-${OMNILUX_REGISTRY_TOKEN:-${GHCR_TOKEN:-}}}"

  local curl_args=(-fsSL)
  if [[ -n "${password}" ]]; then
    if [[ -z "${username}" ]]; then
      die "Set OMNILUX_REGISTRY_USERNAME when using GHCR_TOKEN, OMNILUX_REGISTRY_TOKEN, or OMNILUX_REGISTRY_PASSWORD."
    fi
    curl_args+=(-u "${username}:${password}")
  fi

  token_file="$(mktemp)"
  if ! curl "${curl_args[@]}" "https://${registry}/token?service=${registry}&scope=repository:${repository}:pull" -o "${token_file}"; then
    rm -f "${token_file}"
    return 1
  fi

  if ! token="$(node_json "${token_file}" <<'NODE'
const fs = require('node:fs');
const [tokenFile] = process.argv.slice(2);
const payload = JSON.parse(fs.readFileSync(tokenFile, 'utf8'));
const token = payload.token || payload.access_token;
if (!token) process.exit(1);
process.stdout.write(token);
NODE
  )"; then
    rm -f "${token_file}"
    return 1
  fi

  rm -f "${token_file}"
  printf '%s' "${token}"
}

manifest_accept_header() {
  printf '%s' 'application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json'
}

registry_get_manifest() {
  local registry="$1"
  local repository="$2"
  local reference="$3"
  local token="$4"
  local output_file="$5"

  curl -fsSL \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: $(manifest_accept_header)" \
    "https://${registry}/v2/${repository}/manifests/${reference}" \
    -o "${output_file}"
}

select_platform_manifest_digest() {
  local manifest_file="$1"
  local platform="$2"

  node_json "${platform}" "${manifest_file}" <<'NODE'
const [platform, manifestFile] = process.argv.slice(2);
const fs = require('node:fs');
const manifest = JSON.parse(fs.readFileSync(manifestFile, 'utf8'));
if (!Array.isArray(manifest.manifests)) {
  process.exit(0);
}
const [os, arch] = platform.split('/');
const match = manifest.manifests.find((entry) => (
  entry.platform
  && entry.platform.os === os
  && entry.platform.architecture === arch
));
if (!match) {
  console.error(`No image manifest found for ${platform}. Available: ${manifest.manifests.map((entry) => `${entry.platform?.os ?? 'unknown'}/${entry.platform?.architecture ?? 'unknown'}`).join(', ')}`);
  process.exit(2);
}
process.stdout.write(match.digest);
NODE
}

list_layer_specs() {
  local manifest_file="$1"

  node_json "${manifest_file}" <<'NODE'
const [manifestFile] = process.argv.slice(2);
const fs = require('node:fs');
const manifest = JSON.parse(fs.readFileSync(manifestFile, 'utf8'));
if (!Array.isArray(manifest.layers)) {
  console.error('Selected image manifest has no layers.');
  process.exit(1);
}
for (const layer of manifest.layers) {
  if (layer.mediaType && layer.mediaType.includes('nondistributable')) continue;
  console.log(`${layer.digest} ${layer.mediaType ?? ''}`);
}
NODE
}

image_revision() {
  local manifest_file="$1"
  local registry="$2"
  local repository="$3"
  local token="$4"
  local tmp_dir="$5"

  local config_digest
  config_digest="$(
    node_json "${manifest_file}" <<'NODE'
const [manifestFile] = process.argv.slice(2);
const fs = require('node:fs');
const manifest = JSON.parse(fs.readFileSync(manifestFile, 'utf8'));
process.stdout.write(manifest.config?.digest || '');
NODE
  )"

  if [[ -z "${config_digest}" ]]; then
    printf ''
    return
  fi

  local config_file="${tmp_dir}/config.json"
  curl -fsSL \
    -H "Authorization: Bearer ${token}" \
    "https://${registry}/v2/${repository}/blobs/${config_digest}" \
    -o "${config_file}"

  node_json "${config_file}" <<'NODE'
const [configFile] = process.argv.slice(2);
const fs = require('node:fs');
const config = JSON.parse(fs.readFileSync(configFile, 'utf8'));
process.stdout.write(config.config?.Labels?.['org.opencontainers.image.revision'] || '');
NODE
}

list_layer_entries() {
  local layer_file="$1"
  local media_type="$2"

  case "${media_type}" in
    *zstd*)
      tar --zstd -tf "${layer_file}"
      ;;
    *gzip*|*tar+gzip*)
      tar -tzf "${layer_file}"
      ;;
    *)
      tar -tf "${layer_file}"
      ;;
  esac
}

normalize_layer_path() {
  local entry="$1"
  entry="${entry#./}"
  entry="${entry%/}"

  if [[ -z "${entry}" || "${entry}" == "." ]]; then
    printf ''
    return 0
  fi

  case "${entry}" in
    /*|../*|*/../*|*/..)
      return 1
      ;;
  esac

  printf '%s' "${entry}"
}

apply_layer_whiteouts() {
  local entries_file="$1"
  local rootfs_dir="$2"

  while IFS= read -r raw_entry; do
    local entry dir base target target_dir
    entry="$(normalize_layer_path "${raw_entry}")" || die "Unsafe path in image layer: ${raw_entry}"
    [[ -n "${entry}" ]] || continue
    base="$(basename "${entry}")"
    [[ "${base}" == .wh.* ]] || continue

    dir="$(dirname "${entry}")"
    [[ "${dir}" == "." ]] && dir=""

    if [[ "${base}" == ".wh..wh..opq" ]]; then
      target_dir="${rootfs_dir}/${dir}"
      if [[ -d "${target_dir}" ]]; then
        find "${target_dir}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
      fi
      continue
    fi

    target="${rootfs_dir}/${dir}/${base#.wh.}"
    rm -rf "${target}"
  done < "${entries_file}"
}

prepare_known_symlink_conflicts() {
  local rootfs_dir="$1"
  local conflict

  for conflict in \
    app/apps/server/node_modules/@omnilux/api-contracts \
    app/apps/server/node_modules/@omnilux/plugin-sdk \
    app/apps/server/node_modules/@omnilux/types \
    app/apps/server/node_modules/@shared/playback \
    app/node_modules/@omnilux/api-contracts \
    app/node_modules/@omnilux/plugin-sdk \
    app/node_modules/@omnilux/types \
    app/node_modules/@shared/playback; do
    if [[ -L "${rootfs_dir}/${conflict}" ]]; then
      rm -f "${rootfs_dir}/${conflict}"
    fi
  done
}

extract_layer() {
  local layer_file="$1"
  local media_type="$2"
  local rootfs_dir="$3"
  local entries_file

  entries_file="$(mktemp)"
  list_layer_entries "${layer_file}" "${media_type}" | grep -E '(^|/)\.wh\.' > "${entries_file}" || true
  apply_layer_whiteouts "${entries_file}" "${rootfs_dir}"
  prepare_known_symlink_conflicts "${rootfs_dir}"

  case "${media_type}" in
    *zstd*)
      tar --zstd -xf "${layer_file}" -C "${rootfs_dir}"
      ;;
    *gzip*|*tar+gzip*)
      tar -xzf "${layer_file}" -C "${rootfs_dir}"
      ;;
    *)
      tar -xf "${layer_file}" -C "${rootfs_dir}"
      ;;
  esac

  remove_layer_whiteout_markers "${entries_file}" "${rootfs_dir}"
  rm -f "${entries_file}"
}

remove_layer_whiteout_markers() {
  local entries_file="$1"
  local rootfs_dir="$2"

  while IFS= read -r raw_entry; do
    local entry base
    entry="$(normalize_layer_path "${raw_entry}")" || die "Unsafe path in image layer: ${raw_entry}"
    [[ -n "${entry}" ]] || continue
    base="$(basename "${entry}")"
    [[ "${base}" == .wh.* ]] || continue
    rm -rf "${rootfs_dir}/${entry}"
  done < "${entries_file}"
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

write_launcher() {
  local app_dir="$1"
  install -d -m 0755 -o root -g root "${app_dir}/bin"

  cat > "${app_dir}/bin/omnilux-runtime" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${APP_DIR}"

if [[ -f apps/server/dist/server/src/backend/index.js ]]; then
  exec /usr/bin/node apps/server/dist/server/src/backend/index.js
elif [[ -f apps/server/dist/server/index.js ]]; then
  exec /usr/bin/node apps/server/dist/server/index.js
elif [[ -f apps/server/.output/server/index.mjs ]]; then
  exec /usr/bin/node apps/server/.output/server/index.mjs
fi

echo "No supported OmniLux server entrypoint found in ${APP_DIR}" >&2
exit 1
EOF

  chmod 0755 "${app_dir}/bin/omnilux-runtime"
}

download_runtime_image() {
  local platform
  platform="$(detect_platform)"
  info "Resolving ${OMNILUX_IMAGE} for ${platform}..."

  local image_ref_parts registry repository reference
  image_ref_parts="$(parse_image_ref "${OMNILUX_IMAGE}")"
  registry="$(printf '%s\n' "${image_ref_parts}" | sed -n '1p')"
  repository="$(printf '%s\n' "${image_ref_parts}" | sed -n '2p')"
  reference="$(printf '%s\n' "${image_ref_parts}" | sed -n '3p')"

  local tmp_dir rootfs_dir layers_dir
  tmp_dir="$(mktemp -d)"
  rootfs_dir="${tmp_dir}/rootfs"
  layers_dir="${tmp_dir}/layers"
  _OMNILUX_INSTALL_TMP_DIR="${tmp_dir}"
  mkdir -p "${rootfs_dir}" "${layers_dir}"

  cleanup_tmp() {
    rm -rf "${_OMNILUX_INSTALL_TMP_DIR:-}"
  }
  trap cleanup_tmp EXIT

  local token index_manifest selected_digest manifest_file revision
  token="$(registry_token "${registry}" "${repository}")" || die "Could not get registry token for ${registry}/${repository}. If the image is private, set OMNILUX_REGISTRY_USERNAME and GHCR_TOKEN or OMNILUX_REGISTRY_PASSWORD."
  index_manifest="${tmp_dir}/index.json"
  registry_get_manifest "${registry}" "${repository}" "${reference}" "${token}" "${index_manifest}"

  selected_digest="$(select_platform_manifest_digest "${index_manifest}" "${platform}")"
  manifest_file="${index_manifest}"
  if [[ -n "${selected_digest}" ]]; then
    info "Selected image manifest ${selected_digest}"
    manifest_file="${tmp_dir}/manifest.json"
    registry_get_manifest "${registry}" "${repository}" "${selected_digest}" "${token}" "${manifest_file}"
  fi

  revision="$(image_revision "${manifest_file}" "${registry}" "${repository}" "${token}" "${tmp_dir}")"

  info "Downloading and extracting image layers..."
  while read -r digest media_type; do
    [[ -n "${digest}" ]] || continue
    local safe_digest layer_file
    safe_digest="${digest//[:\/]/_}"
    layer_file="${layers_dir}/${safe_digest}.tar"
    curl -fsSL \
      -H "Authorization: Bearer ${token}" \
      "https://${registry}/v2/${repository}/blobs/${digest}" \
      -o "${layer_file}"
    extract_layer "${layer_file}" "${media_type}" "${rootfs_dir}"
    rm -f "${layer_file}"
  done < <(list_layer_specs "${manifest_file}")

  if [[ ! -d "${rootfs_dir}/app" ]]; then
    die "Published image did not contain /app. Cannot install bare-metal runtime."
  fi

  local staging_dir previous_dir timestamp
  staging_dir="$(mktemp -d "${OMNILUX_APP_DIR}.staging.XXXXXX")"
  cp -a "${rootfs_dir}/app/." "${staging_dir}/"
  materialize_esm_symlinks "${staging_dir}"
  write_launcher "${staging_dir}"

  chown -R root:root "${staging_dir}"
  find "${staging_dir}" -type d -exec chmod 0755 {} +
  find "${staging_dir}" -type f -exec chmod u=rw,go=r {} +
  chmod 0755 "${staging_dir}/bin/omnilux-runtime"
  [[ -f "${staging_dir}/entrypoint.sh" ]] && chmod 0755 "${staging_dir}/entrypoint.sh"

  timestamp="$(date +%Y%m%d%H%M%S)"
  previous_dir="${OMNILUX_APP_DIR}.previous"

  if systemctl list-unit-files "${OMNILUX_SERVICE_NAME}.service" >/dev/null 2>&1 && systemctl is-active "${OMNILUX_SERVICE_NAME}.service" >/dev/null 2>&1; then
    info "Stopping ${OMNILUX_SERVICE_NAME}.service for runtime replacement..."
    systemctl stop "${OMNILUX_SERVICE_NAME}.service"
  fi

  rm -rf "${previous_dir}"
  if [[ -e "${OMNILUX_APP_DIR}" ]]; then
    mv "${OMNILUX_APP_DIR}" "${previous_dir}"
  fi
  mv "${staging_dir}" "${OMNILUX_APP_DIR}"

  cat > "${INSTALL_METADATA_FILE}" <<EOF
{
  "image": "${OMNILUX_IMAGE}",
  "platform": "${platform}",
  "manifest": "${selected_digest:-${reference}}",
  "revision": "${revision}",
  "installedAt": "${timestamp}",
  "runtimeDir": "${OMNILUX_APP_DIR}",
  "previousRuntimeDir": "${previous_dir}"
}
EOF
  chown root:"${OMNILUX_GROUP}" "${INSTALL_METADATA_FILE}"
  chmod 0640 "${INSTALL_METADATA_FILE}"

  ok "Installed runtime from ${OMNILUX_IMAGE}${revision:+ (${revision:0:12})}"
  cleanup_tmp
  unset _OMNILUX_INSTALL_TMP_DIR
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
    printf '%s=%s\n' "${key}" "${value}" >> "${ENV_FILE}"
  fi
}

write_env_file() {
  if [[ ! -f "${ENV_FILE}" ]]; then
    cat > "${ENV_FILE}" <<EOF
# OmniLux bare-metal Linux runtime configuration.
# Edit this file, then run: sudo systemctl restart ${OMNILUX_SERVICE_NAME}
EOF
  fi

  append_env_default "NODE_ENV" "production"
  append_env_default "PORT" "${OMNILUX_PORT}"
  append_env_default "OMNILUX_DEPLOYMENT_PROFILE" "self-hosted"
  append_env_default "OMNILUX_PRIMARY_DEPLOYMENT" "bare-metal-linux"
  append_env_default "OMNILUX_DATA_DIR" "${OMNILUX_DATA_DIR}"
  append_env_default "OMNILUX_DB_PATH" "${OMNILUX_DATA_DIR}/omnilux.db"
  append_env_default "OMNILUX_LIBRARY_ROOT" "${OMNILUX_MEDIA_DIR}"
  append_env_default "OMNILUX_DOWNLOAD_PATH" "${OMNILUX_DATA_DIR}/downloads"
  append_env_default "OMNILUX_PLUGINS_DIR" "${OMNILUX_PLUGINS_DIR}"
  append_env_default "OMNILUX_CLOUD_URL" "https://api.omnilux.tv"
  append_env_default "OMNILUX_CLOUD_APP_URL" "https://app.omnilux.tv"
  append_env_default "OMNILUX_RELAY_URL" "wss://relay.omnilux.tv/ws/server"
  append_env_default "OMNILUX_ENTITLEMENT_LEASE_PUBLIC_KEY_SPKI_B64URL" ""
  append_env_default "OMNILUX_ALLOW_UNSIGNED_ENTITLEMENT_LEASES" "false"
  append_env_default "OMNILUX_PUBLIC_ORIGIN" "${OMNILUX_PUBLIC_ORIGIN}"
  append_env_default "OMNILUX_ALLOWED_ORIGINS" "${OMNILUX_PUBLIC_ORIGIN}"
  append_env_default "OMNILUX_BROWSER_SOLVER" "auto"
  append_env_default "TMDB_API_KEY" "${TMDB_API_KEY}"
  append_env_default "LOG_LEVEL" "info"

  chown root:"${OMNILUX_GROUP}" "${ENV_FILE}"
  chmod 0640 "${ENV_FILE}"
  ok "Environment file is ready at ${ENV_FILE}"
}

write_systemd_service() {
  cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=OmniLux self-hosted runtime
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=${OMNILUX_USER}
Group=${OMNILUX_GROUP}
WorkingDirectory=${OMNILUX_APP_DIR}
EnvironmentFile=${ENV_FILE}
ExecStart=${OMNILUX_APP_DIR}/bin/omnilux-runtime
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
KillSignal=SIGTERM
UMask=0027

# Basic hardening while preserving access to media and runtime state.
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectControlGroups=true
ProtectKernelModules=true
ProtectKernelTunables=true
RestrictSUIDSGID=true
ReadWritePaths=${OMNILUX_DATA_DIR} ${OMNILUX_PLUGINS_DIR} ${OMNILUX_MEDIA_DIR}

[Install]
WantedBy=multi-user.target
EOF

  chmod 0644 "${SERVICE_FILE}"
  systemctl daemon-reload
  systemctl enable "${OMNILUX_SERVICE_NAME}.service" >/dev/null
  ok "systemd service installed at ${SERVICE_FILE}"
}

start_and_check_service() {
  if [[ "${OMNILUX_START_SERVICE}" != "1" ]]; then
    warn "Skipping service start because OMNILUX_START_SERVICE=${OMNILUX_START_SERVICE}"
    return
  fi

  info "Starting ${OMNILUX_SERVICE_NAME}.service..."
  systemctl restart "${OMNILUX_SERVICE_NAME}.service"

  local health_url="http://127.0.0.1:${OMNILUX_PORT}/api/health"
  for _ in $(seq 1 30); do
    if curl -fsS "${health_url}" >/dev/null 2>&1; then
      ok "OmniLux is healthy at ${health_url}"
      return
    fi
    sleep 2
  done

  warn "Service did not pass health check within 60 seconds."
  warn "Recent logs:"
  journalctl -u "${OMNILUX_SERVICE_NAME}.service" -n 80 --no-pager || true
  exit 1
}

check_installation() {
  detect_supported_os
  command -v curl >/dev/null || die "curl is missing"
  command -v ffmpeg >/dev/null || die "ffmpeg is missing"
  command -v tar >/dev/null || die "tar is missing"
  [[ "$(node_major)" == "${NODE_MAJOR}" ]] || die "Node ${NODE_MAJOR}.x is required"
  test -x "${OMNILUX_APP_DIR}/bin/omnilux-runtime" || die "Runtime launcher missing at ${OMNILUX_APP_DIR}/bin/omnilux-runtime"
  test -f "${SERVICE_FILE}" || die "systemd service missing at ${SERVICE_FILE}"
  systemctl is-enabled "${OMNILUX_SERVICE_NAME}.service" >/dev/null
  systemctl is-active "${OMNILUX_SERVICE_NAME}.service" >/dev/null
  curl -fsS "http://127.0.0.1:${OMNILUX_PORT}/api/health" >/dev/null
  ok "Bare-metal installation checks passed"
}

install_or_upgrade() {
  detect_supported_os
  ensure_system_packages
  ensure_node
  ensure_user_and_dirs
  download_runtime_image
  write_env_file
  write_systemd_service
  start_and_check_service
}

main() {
  local command="${1:-install}"
  case "${command}" in
    -h|--help|help)
      usage
      ;;
    install|upgrade)
      require_root "$@"
      install_or_upgrade
      ;;
    check)
      require_root "$@"
      check_installation
      ;;
    *)
      usage
      die "Unknown command: ${command}"
      ;;
  esac
}

main "$@"
