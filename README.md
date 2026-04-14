# omnilux-deploy

Self-hosted deployment repo for OmniLux.

This repo is the official deployment contract for the self-hosted OmniLux runtime.

Canonical note:

- `omnilux/` is the self-hosted runtime product that uses this repo
- `media.omnilux.tv` is owned by `omnilux-media`
- `ops.omnilux.tv` is owned by `omnilux-ops`
- this repo no longer owns first-party managed runtime or ops deploy contracts

This repo contains the canonical self-hosted deploy assets that previously lived in `../omnilux/`:

- `docker/`
- `docker-compose.truenas.yml`
- `deploy/`
- `scripts/deploy.sh`
- `scripts/deploy.example.sh`
- `scripts/install.sh`
- `scripts/install/`
- `scripts/entrypoint.sh`
- `scripts/tailscale-serve.json`

What this repo owns:

- Dockerfiles and Compose bundles for self-hosted installs
- the supported env/deploy contract for official self-hosted installs
- Host bootstrap and install scripts
- TrueNAS deployment flow
- Kubernetes deploy assets
- Entrypoints and deploy-time helpers

Current deployment notes:

- `scripts/deploy.sh`, `scripts/deploy.example.sh`, `scripts/install.sh`, `docker-compose.truenas.yml`, and the `docker/` compose bundle deploy published images and do not require product source on the target host.
- `scripts/install/install-linux.sh`, `scripts/install/install-macos.sh`, `scripts/install/install-windows.ps1`, and `scripts/install/setup.sh` are retired source-build paths that point users back to the supported image-based flows.

Explicitly not copied in this pass:

- `../omnilux/apps/`
- `../omnilux/packages/`
- `../omnilux/scripts/check-runtime.mjs`
- `../omnilux/scripts/prepare-web-smoke.mjs`
- `../omnilux/scripts/start-web-smoke-server.mjs`
- `../omnilux/scripts/run-remote-smoke.sh`
- `../omnilux/scripts/starter-library/`

Runtime deploy assumptions:

- `docker-compose.truenas.yml` now pulls `${OMNILUX_IMAGE:-ghcr.io/omnilux-tv/omnilux:latest}` at deploy time.
- self-hosted cloud-linked traffic should target the branded public control-plane endpoint `https://api.omnilux.tv` instead of a raw `*.supabase.co` URL.
- deployment profiles are opt-in:
  - `OMNILUX_DEPLOYMENT_PROFILE=self-hosted` for normal customer installs
- `OMNILUX_PUBLIC_ORIGIN`, `OMNILUX_CLOUD_APP_URL`, and `OMNILUX_ALLOWED_ORIGINS` let the self-hosted runtime image declare the correct public hostname and browser origins.
- `scripts/deploy.sh` and `scripts/deploy.example.sh` sync only deploy-owned assets and then pull the selected image tag on the target host.
- `docker/docker-compose.yml` and `docker/docker-compose.example.yml` are local image-based examples, not source-build inputs.
- installed plugins must persist across recreates, so the deploy contract now binds `/app/plugins` and sets `OMNILUX_PLUGINS_DIR=/app/plugins`
- first-party managed runtime deploy contracts now live in `../omnilux-media/`
- first-party operator-console image publishing and deploy ownership now live in `../omnilux-ops/`
- `docs/first-party-runtime-profiles.md` is now an archive note that points readers to the dedicated repos

Image publishing ownership:

- `ghcr.io/omnilux-tv/omnilux` is published from `../omnilux/.github/workflows/docker-publish.yml`.
- This repo remains deploy-only and should not own product image publishing.
