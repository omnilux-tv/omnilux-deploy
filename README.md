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

- `docker/Dockerfile.server` still builds against the full OmniLux product checkout layout and expects `apps/`, `packages/`, workspace manifests, and migrations from `../omnilux/` to exist in the build context.
- `scripts/deploy.sh` and `scripts/deploy.example.sh` are now rewired to sync a sibling `omnilux/` checkout on purpose via `OMNILUX_PRODUCT_REPO`, but the remote deploy root still ends up with the combined product+deploy tree.
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

Current transitional checkout assumptions:

- `../omnilux/` is the default sibling product repo used by the copied Docker and deploy scripts
- `OMNILUX_PRODUCT_REPO` can override that path when the workspace layout differs

CI ownership:

- `.github/workflows/docker-publish.yml` owns the container publish flow for the extracted deploy repo.
