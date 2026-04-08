#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
This post-clone source-build setup script has been retired.

Supported personal self-hosted paths now use the published OmniLux image instead:

1. Run `scripts/install.sh` for the default image-based local install flow.
2. Or copy `docker/docker-compose.example.yml` and run `docker compose pull && docker compose up -d`.

This repo is deploy-only and no longer acts as the OmniLux runtime source tree.
EOF

exit 1
