# omnilux-deploy

Self-hosted deployment repo for OmniLux.

This repo is also the official deployment contract for first-party managed OmniLux runtimes. The same image and compose-level env contract should be able to deploy:

- normal customer self-hosted servers
- the managed media runtime profile
- the internal ops runtime profile

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
- the supported env/deploy contract for customer-compatible first-party installs
- Host bootstrap and install scripts
- TrueNAS deployment flow
- Kubernetes deploy assets
- Entrypoints and deploy-time helpers

What is still transitional:

- `scripts/deploy.sh`, `scripts/deploy.example.sh`, `scripts/install.sh`, `docker-compose.truenas.yml`, and the `docker/` compose bundle now deploy published images and no longer require product source on the target host.
- `scripts/install/install-linux.sh`, `scripts/install/install-macos.sh`, `scripts/install/install-windows.ps1`, and `scripts/install/setup.sh` are explicitly retired source-build paths that point users back to the supported image-based flows.

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
- self-hosted cloud-linked traffic should target the branded public control-plane endpoint `https://api.omnilux.tv` instead of a raw `*.supabase.co` URL.
- deployment profiles are opt-in:
  - `OMNILUX_DEPLOYMENT_PROFILE=self-hosted` for normal customer installs
  - `OMNILUX_DEPLOYMENT_PROFILE=managed-media` for `media.omnilux.tv`
  - `OMNILUX_DEPLOYMENT_PROFILE=ops` for `ops.omnilux.tv`
- `OMNILUX_PUBLIC_ORIGIN`, `OMNILUX_CLOUD_APP_URL`, and `OMNILUX_ALLOWED_ORIGINS` let the same runtime image declare the correct public hostname and browser origins for first-party managed installs.
- `scripts/deploy.sh` and `scripts/deploy.example.sh` sync only deploy-owned assets and then pull the selected image tag on the target host.
- `docker/docker-compose.yml` and `docker/docker-compose.example.yml` are local image-based examples, not source-build inputs.
- `deploy/first-party/docker-compose.runtime.yml` is the dedicated-host compose contract for first-party `managed-media` and `ops` runtimes.
- `deploy/first-party/managed-media.env.example` and `deploy/first-party/ops.env.example` are the official profile-specific env templates for first-party installs.
- `docs/first-party-runtime-profiles.md` describes when to use edge-hosted profiles versus dedicated runtime hosts.

Image publishing ownership:

- `ghcr.io/omnilux-tv/omnilux` is published from `../omnilux/.github/workflows/docker-publish.yml`.
- This repo remains deploy-only and should not own product image publishing.
