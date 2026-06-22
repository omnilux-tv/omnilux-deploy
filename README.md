# omnilux-deploy

Self-hosted deployment repo for OmniLux.

## Workspace

This repository is part of the official OmniLux multi-repo workspace. Use the root `omnilux-workspace` repo for onboarding, profiles, and cross-repo contracts:

- Onboarding: `../ONBOARDING.md`
- Manifest: `../workspace.repositories.json`
- Contracts: `../contracts/`

This repo is the official deployment contract for the self-hosted OmniLux runtime.

## Canonical Contracts

- Deployment contract: `../contracts/deployment-contract-plan.md`
- Runtime architecture: `../omnilux/docs/ARCHITECTURE.md`
- Workspace plane map: `../ARCHITECTURE.md`

Deploy docs should own reusable self-hosted install, upgrade, rollback, env, volume, and health-check behavior. Runtime behavior belongs in `../omnilux/`; public ingress belongs in `../omnilux-edge/`.

Canonical note:

- `omnilux/` is the self-hosted runtime product that uses this repo
- `media.omnilux.tv` is owned by `omnilux-media`
- `ops.omnilux.tv` is owned by `omnilux-ops`
- this repo no longer owns first-party managed runtime or ops deploy contracts

Self-hosted setup:

- Universal Docker/image path: [`docs/self-hosted-setup.md`](docs/self-hosted-setup.md)
- Bare-metal Linux native service path: [`docs/bare-metal-linux.md`](docs/bare-metal-linux.md)
- Bare-metal macOS user service path: [`docs/bare-metal-macos.md`](docs/bare-metal-macos.md)
- Runtime management CLI: [`docs/runtime-cli.md`](docs/runtime-cli.md)
- Optional compose env template: [`env/example.env`](env/example.env)

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
- `scripts/install/install-linux.sh` is the supported bare-metal Linux path. It extracts the published runtime image from GHCR and installs it as a native `systemd` service without Docker or source repository access.
- `scripts/install/install-macos.sh` is the supported bare-metal macOS path. It installs a Darwin-built runtime tarball as a user-level `launchd` service without Docker or source repository access.
- `scripts/omnilux` is the post-install runtime management CLI installed by the supported Docker, Linux, and macOS installers.
- `scripts/install/install-windows.ps1` and `scripts/install/setup.sh` are retired legacy paths that point users back to the supported image-based flows.

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
- production cloud-linked entitlement checks require `OMNILUX_ENTITLEMENT_LEASE_PUBLIC_KEY_SPKI_B64URL`; `OMNILUX_ALLOW_UNSIGNED_ENTITLEMENT_LEASES=true` is only a temporary migration override.
- cloud/edge infrastructure validation should use the VPS validation lane when
  Docker or Caddy behavior matters: disposable containers on the VPS Docker
  context, no production bind mounts, no live Supabase database mutation, and no
  live Caddy reload before the explicit deploy step. Current IONOS context:
  `omnilux-vps` -> `ssh://deploy@omnilux.tv`.
- deployment profiles are opt-in:
  - `OMNILUX_DEPLOYMENT_PROFILE=self-hosted` for normal customer installs
  - `OMNILUX_PRIMARY_DEPLOYMENT=docker-compose` for the minimal Docker path
  - `OMNILUX_PRIMARY_DEPLOYMENT=truenas-custom-app` for the TrueNAS Compose path
  - `OMNILUX_PRIMARY_DEPLOYMENT=bare-metal-linux` for the native Linux path
  - `OMNILUX_PRIMARY_DEPLOYMENT=bare-metal-macos` for the native macOS path
- the TrueNAS updater sidecar is opt-in with `COMPOSE_PROFILES=updater` because
  it mounts `/var/run/docker.sock`; keep it disabled unless web-triggered
  updates are required, and set both `OMNILUX_UPDATER_URL` and a long random
  `OMNILUX_UPDATER_TOKEN` when enabling it
- `OMNILUX_PUBLIC_ORIGIN`, `OMNILUX_CLOUD_APP_URL`, and `OMNILUX_ALLOWED_ORIGINS` let the self-hosted runtime image declare the correct public hostname and browser origins.
- `scripts/deploy.sh` and `scripts/deploy.example.sh` sync only deploy-owned assets and then pull the selected image tag on the target host.
- `docker/docker-compose.yml` and `docker/docker-compose.example.yml` are local image-based examples, not legacy build inputs.
- `scripts/install/install-linux.sh` is image-based but not Docker-based: it downloads the public image layers through the OCI registry API, extracts `/app`, and runs the built runtime with host Node.js under `systemd`.
- `scripts/install/install-macos.sh` is artifact-based and not Docker-based: it downloads a public Darwin tarball such as `omnilux-darwin-arm64.tar.gz`, installs it under the current user's `~/Library/Application Support/OmniLux`, and runs it with `launchd`.
- installed plugins must persist across recreates, so the deploy contract now binds `/app/plugins` and sets `OMNILUX_PLUGINS_DIR=/app/plugins`
- first-party managed runtime deploy contracts now live in `../omnilux-media/`
- first-party operator-console image publishing and deploy ownership now live in `../omnilux-ops/`
- `docs/first-party-runtime-profiles.md` is now an archive note that points readers to the dedicated repos

Image publishing ownership:

- `ghcr.io/omnilux-tv/omnilux` is published from `../omnilux/.github/workflows/docker-publish.yml`.
- This repo remains deploy-only and should not own product image publishing.

Pulling that image on any host requires registry access GitHub allows for the package: either the package is **public** (anonymous `docker pull` and anonymous OCI layer download work) or the host runs **`docker login ghcr.io`** with credentials that have **`read:packages`**. Host-specific paths, TrueNAS app fields, and machine-specific compose overrides belong outside this repo, not in `omnilux-deploy`.
