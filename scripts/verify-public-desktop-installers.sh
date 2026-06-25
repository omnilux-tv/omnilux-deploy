#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_URL="${OMNILUX_INSTALLER_RELEASE_BASE_URL:-https://github.com/omnilux-tv/omnilux-deploy/releases/latest/download}"
REPO="${OMNILUX_INSTALLER_RELEASE_REPO:-omnilux-tv/omnilux-deploy}"
WORKFLOW="${OMNILUX_INSTALLER_RELEASE_WORKFLOW:-Desktop Installers}"
EXPECTED_SHA="${OMNILUX_INSTALLER_EXPECTED_SHA:-$(git -C "${ROOT}" rev-parse HEAD)}"

command -v gh >/dev/null 2>&1 || {
  echo "gh is required to verify the desktop installer release workflow revision." >&2
  exit 1
}

for asset in \
  OmniLux-macOS.pkg \
  OmniLux-macOS.pkg.sha256 \
  OmniLux-Linux.AppImage \
  OmniLux-Linux.AppImage.sha256 \
  OmniLux-Setup.exe \
  OmniLux-Setup.exe.sha256; do
  curl -fsIL --retry 2 --retry-delay 1 "${BASE_URL}/${asset}" >/dev/null || {
    echo "Missing public desktop installer asset: ${BASE_URL}/${asset}" >&2
    exit 1
  }
done

latest_success="$(gh run list \
  --repo "${REPO}" \
  --workflow "${WORKFLOW}" \
  --status success \
  --limit 1 \
  --json databaseId,headSha,url \
  --jq 'if length == 0 then empty else .[0] | [.databaseId, .headSha, .url] | @tsv end')"

if [[ -z "${latest_success}" ]]; then
  echo "No successful ${WORKFLOW} workflow run exists for ${REPO}." >&2
  exit 1
fi

IFS=$'\t' read -r latest_id latest_sha latest_url <<<"${latest_success}"

if [[ "${latest_sha}" != "${EXPECTED_SHA}" ]]; then
  echo "Latest public desktop installer workflow success is not from the expected revision." >&2
  echo "Expected: ${EXPECTED_SHA}" >&2
  echo "Actual:   ${latest_sha} (${latest_url})" >&2
  exit 1
fi

echo "Public desktop installer assets are available from workflow run ${latest_id}."
