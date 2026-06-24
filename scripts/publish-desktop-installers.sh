#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_TAG="${1:-}"
REPO="${OMNILUX_INSTALLER_RELEASE_REPO:-omnilux-tv/omnilux-deploy}"
WORKFLOW="Desktop Installers"

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/publish-desktop-installers.sh <release-tag>

Triggers the Desktop Installers workflow, waits for it to finish, and verifies
the public latest-release installer assets.

Set OMNILUX_INSTALLER_RELEASE_REPO=owner/repo to override the GitHub repo.
USAGE
  exit 2
}

[[ -n "${RELEASE_TAG}" && "${RELEASE_TAG}" != "-h" && "${RELEASE_TAG}" != "--help" ]] || usage
command -v gh >/dev/null 2>&1 || {
  echo "gh is required to publish desktop installers." >&2
  exit 1
}
command -v curl >/dev/null 2>&1 || {
  echo "curl is required to verify public installer assets." >&2
  exit 1
}

node "${ROOT}/scripts/validate-desktop-installers.mjs"
bash -n "${ROOT}/scripts/package-macos-pkg.sh" "${ROOT}/installer/linux/AppRun"

before_ids="$(gh run list --repo "${REPO}" --workflow "${WORKFLOW}" --limit 20 --json databaseId --jq '.[].databaseId')"
gh workflow run "${WORKFLOW}" --repo "${REPO}" --field "release_tag=${RELEASE_TAG}"

run_id=""
for _ in {1..30}; do
  candidate="$(gh run list --repo "${REPO}" --workflow "${WORKFLOW}" --limit 10 --json databaseId --jq '.[].databaseId' | while read -r id; do
    if ! grep -qx "${id}" <<<"${before_ids}"; then
      printf '%s\n' "${id}"
      break
    fi
  done)"
  if [[ -n "${candidate}" ]]; then
    run_id="${candidate}"
    break
  fi
  sleep 2
done

if [[ -z "${run_id}" ]]; then
  echo "Unable to find the triggered Desktop Installers workflow run." >&2
  exit 1
fi

gh run watch "${run_id}" --repo "${REPO}" --exit-status
"${ROOT}/scripts/verify-public-desktop-installers.sh"

echo "Desktop installers published for ${RELEASE_TAG} via workflow run ${run_id}."
