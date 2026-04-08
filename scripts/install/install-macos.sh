#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
This source-build macOS installer has been retired.

Supported personal self-hosted paths now use the published OmniLux image instead:

1. Run `scripts/install.sh` for the default image-based local install flow.
2. Or copy `docker/docker-compose.example.yml` and run `docker compose pull && docker compose up -d`.

This repo no longer supports building OmniLux from source or managing a native
launchd service from `omnilux-deploy`.
EOF

exit 1
