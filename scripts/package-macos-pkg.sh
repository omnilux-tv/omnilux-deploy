#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export COPYFILE_DISABLE=1
VERSION="${OMNILUX_INSTALLER_VERSION:-0.1.0}"
VERSION="${VERSION#v}"
OUT_DIR="${OMNILUX_INSTALLER_OUT_DIR:-${ROOT}/dist/installers}"
WORK_DIR="$(mktemp -d)"
PKG_SIGN_IDENTITY="${OMNILUX_MACOS_INSTALLER_SIGN_IDENTITY:-}"
NOTARY_KEYCHAIN_PROFILE="${OMNILUX_NOTARYTOOL_KEYCHAIN_PROFILE:-}"

cleanup() {
  rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

die() {
  printf '[error] %s\n' "$*" >&2
  exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || die "macOS installer packages must be built on macOS."
command -v pkgbuild >/dev/null 2>&1 || die "pkgbuild is required."

PAYLOAD_ROOT="${WORK_DIR}/payload"
SCRIPTS_DIR="${WORK_DIR}/scripts"
UNSIGNED_PKG_PATH="${WORK_DIR}/OmniLux-macOS.unsigned.pkg"
PKG_PATH="${OUT_DIR}/OmniLux-macOS.pkg"

mkdir -p "${PAYLOAD_ROOT}" "${SCRIPTS_DIR}" "${OUT_DIR}"

cat >"${SCRIPTS_DIR}/postinstall" <<'POSTINSTALL'
#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="/var/log/omnilux-macos-installer.log"
INSTALLER_URL="${OMNILUX_MACOS_INSTALLER_URL:-https://omnilux.tv/self-hosted/macos/install.sh}"

log() {
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >>"${LOG_FILE}"
}

console_user="$(stat -f '%Su' /dev/console)"
if [[ -z "${console_user}" || "${console_user}" == "root" ]]; then
  log "No non-root console user is logged in; installed installer payload only."
  exit 0
fi

user_home="$(dscl . -read "/Users/${console_user}" NFSHomeDirectory | awk '{print $2}')"
if [[ -z "${user_home}" || ! -d "${user_home}" ]]; then
  log "Could not resolve home directory for ${console_user}."
  exit 1
fi

uid="$(id -u "${console_user}")"
log "Running OmniLux user-level installer for ${console_user}."

launchctl asuser "${uid}" sudo -u "${console_user}" \
  HOME="${user_home}" \
  OMNILUX_MACOS_INSTALLER_URL="${INSTALLER_URL}" \
  /bin/bash -lc 'curl -fsSL "${OMNILUX_MACOS_INSTALLER_URL}" | bash -s -- install' >>"${LOG_FILE}" 2>&1

log "OmniLux macOS install completed."
POSTINSTALL
chmod 0755 "${SCRIPTS_DIR}/postinstall"

find "${PAYLOAD_ROOT}" "${SCRIPTS_DIR}" -name '._*' -delete
xattr -cr "${PAYLOAD_ROOT}" "${SCRIPTS_DIR}" 2>/dev/null || true

pkgbuild \
  --root "${PAYLOAD_ROOT}" \
  --scripts "${SCRIPTS_DIR}" \
  --identifier "tv.omnilux.macos-installer" \
  --version "${VERSION}" \
  --install-location "/" \
  "${UNSIGNED_PKG_PATH}"

if [[ -n "${PKG_SIGN_IDENTITY}" ]]; then
  productsign --sign "${PKG_SIGN_IDENTITY}" "${UNSIGNED_PKG_PATH}" "${PKG_PATH}"
else
  cp "${UNSIGNED_PKG_PATH}" "${PKG_PATH}"
fi

if [[ -n "${NOTARY_KEYCHAIN_PROFILE}" ]]; then
  xcrun notarytool submit "${PKG_PATH}" --keychain-profile "${NOTARY_KEYCHAIN_PROFILE}" --wait
  xcrun stapler staple "${PKG_PATH}"
fi

shasum -a 256 "${PKG_PATH}" > "${PKG_PATH}.sha256"

printf 'Created %s\n' "${PKG_PATH}"
