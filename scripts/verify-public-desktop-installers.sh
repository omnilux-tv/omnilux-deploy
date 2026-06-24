#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${OMNILUX_INSTALLER_RELEASE_BASE_URL:-https://github.com/omnilux-tv/omnilux-deploy/releases/latest/download}"

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

echo "Public desktop installer assets are available."
