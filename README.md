# omnilux-deploy

Self-hosted deployment repo for OmniLux.

This repo now contains the extracted canonical self-hosted deploy assets that previously lived in `../omnilux/`:

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
- Host bootstrap and install scripts
- TrueNAS deployment flow
- Kubernetes deploy assets
- Entrypoints and deploy-time helpers

What is still transitional:

- `docker/Dockerfile.server` still builds against the full OmniLux product checkout layout in CI, because the published server image is assembled from `omnilux/` plus `omnilux-deploy/` assets.
- `scripts/deploy.sh` and `scripts/deploy.example.sh` now deploy published images and no longer require product source on the target host.
- `scripts/install/install-linux.sh`, `scripts/install/install-macos.sh`, `scripts/install/install-windows.ps1`, and `scripts/install/setup.sh` still target a full product checkout for source builds and service startup.
- Docker/image publishing CI now lives in `.github/workflows/docker-publish.yml`, but it still assembles a combined build context from sibling `omnilux/` source during CI.

Explicitly not copied in this pass:

- `../omnilux/apps/`
- `../omnilux/packages/`
- `../omnilux/scripts/check-runtime.mjs`
- `../omnilux/scripts/prepare-web-smoke.mjs`
- `../omnilux/scripts/start-web-smoke-server.mjs`
- `../omnilux/scripts/run-remote-smoke.sh`
- `../omnilux/scripts/starter-library/`

Follow-up extraction work will need to rewire the copied deploy assets so they consume released product artifacts or a sibling `omnilux/` checkout without treating this repo as the runtime source of truth.

Runtime deploy assumptions:

- `docker-compose.truenas.yml` now pulls `${OMNILUX_IMAGE:-ghcr.io/omnilux-tv/omnilux:latest}` at deploy time.
- `scripts/deploy.sh` and `scripts/deploy.example.sh` sync only deploy-owned assets and then pull the selected image tag on the target host.

CI ownership:

- `.github/workflows/docker-publish.yml` owns the container publish flow for the extracted deploy repo.
