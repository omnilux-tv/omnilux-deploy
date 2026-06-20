#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
This legacy setup path has been retired.

Supported self-hosted install paths now use the published OmniLux runtime:

1. Run `scripts/install.sh` for the default image-based local install flow.
2. Or copy `docker/docker-compose.example.yml` and run `docker compose pull && docker compose up -d`.

Use the published installer or Compose bundle for self-hosted installs.
EOF

exit 1
