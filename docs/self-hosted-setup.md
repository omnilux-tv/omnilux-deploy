# Self-hosted OmniLux server setup

Universal steps for any Docker host. Official compose contracts live in this repo; **host-specific paths and secrets** belong in a private repo (for example `omnilux-infra`), not here.

## 1. What you run

- **Published image:** `ghcr.io/omnilux-tv/omnilux` (tags such as `latest` or a release tag). Built from `omnilux` via [docker-publish workflow](https://github.com/omnilux-tv/omnilux/blob/main/.github/workflows/docker-publish.yml) on pushes to `main` and version tags.
- **Compose:** use `docker-compose.truenas.yml` for GPU / DLNA / updater sidecar patterns, or `scripts/install.sh` for a minimal single-container layout under `~/.omnilux`.
- **CLI:** use [`omnilux`](runtime-cli.md) after installation for status, restart, services, plugins, auth, updates, logs, media, and cloud connection checks.

The minimal Docker path uses `OMNILUX_DEPLOYMENT_PROFILE=self-hosted` with
`OMNILUX_PRIMARY_DEPLOYMENT=docker-compose`. The TrueNAS Compose path uses the
same profile with `OMNILUX_PRIMARY_DEPLOYMENT=truenas-custom-app`.

## 2. Registry access (required if pulls fail with `unauthorized`)

GitHub Container Registry only allows pulls the package policy allows:

| Situation | What to do |
| --- | --- |
| Package is **public** | No login; `docker pull ghcr.io/omnilux-tv/omnilux:latest` works from any host. |
| Package is **private** | On the host: `docker login ghcr.io` with a GitHub username and a PAT that has **`read:packages`**. **TrueNAS Scale:** set **registry authentication** for `ghcr.io` in the Custom App (username + PAT), or run `docker login` as the same user context that runs `docker compose` (often `sudo docker login` so credentials land in root’s Docker config). |

Until the host can pull successfully, you will keep running an **old cached** image layer.

## 3. Persistence (do not skip)

The runtime needs durable host paths for:

- **Application data** (SQLite DB, local state): mounted at `/app/data` in the container (`OMNILUX_DB_PATH` defaults to `/app/data/omnilux.db`).
- **Plugins:** `/app/plugins`.
- **Media library:** mounted at `/data` (`OMNILUX_LIBRARY_ROOT=/data` inside the container).

`docker-compose.truenas.yml` maps those via **`OMNILUX_STORAGE_ROOT`** (data + plugins + updater `repo` sibling layout) and **`OMNILUX_MEDIA_ROOT`**. Override the defaults with environment variables so they match **your** disks. See `env/example.env` for the full list of substitution variables.

## 4. Container hardening defaults

The official Docker and TrueNAS Compose contracts set `security_opt:
no-new-privileges:true`. Keep that enabled in host-specific overrides unless you
have tested a specific platform feature that requires changing it.

The TrueNAS contract still grants `NET_ADMIN` and GPU devices to the main
runtime because those are platform features of that profile. Do not copy those
permissions into the minimal Docker contract unless you are enabling the
matching feature and have a host-local rollback plan.

The `omnilux-updater` sidecar is more sensitive because it mounts
`/var/run/docker.sock`. It is now opt-in behind the Compose `updater` profile.
Leave that profile disabled unless you need web-triggered updates. If you enable
it, set `OMNILUX_UPDATER_URL=http://omnilux-updater:4050` and a long random
`OMNILUX_UPDATER_TOKEN`; rotate the token when operator access changes.

## 5. Bring the stack up

From the directory that contains your compose file:

```bash
docker login ghcr.io   # if required (see §2)
docker compose -f docker-compose.truenas.yml pull omnilux
docker compose -f docker-compose.truenas.yml up -d --build
```

If you enable the updater sidecar, include the profile and pass the same token to
both services:

```bash
COMPOSE_PROFILES=updater \
OMNILUX_UPDATER_URL=http://omnilux-updater:4050 \
OMNILUX_UPDATER_TOKEN=<long-random-token> \
  docker compose -f docker-compose.truenas.yml up -d --build
```

Leaving `OMNILUX_UPDATER_TOKEN` unset disables the updater control API; it does
not create an unauthenticated updater.

The updater waits for `OMNILUX_HEALTH_URL` after recreating the runtime. The
default is `http://omnilux:4000/api/health`; override
`OMNILUX_HEALTH_TIMEOUT_MS` or `OMNILUX_HEALTH_INTERVAL_MS` only when the host
needs a longer startup window.

Health: `GET http://<host>:<mapped-port>/api/health` (default TrueNAS mapping in the contract file is `38400:4000`).

After a `scripts/install.sh` install, use:

```bash
omnilux status
omnilux logs --follow
omnilux restart
```

## 6. Stay on a current image

After registry access works:

```bash
omnilux update --run
docker compose -f docker-compose.truenas.yml pull omnilux
docker compose -f docker-compose.truenas.yml up -d omnilux
```

Pin **`OMNILUX_IMAGE`** to a specific tag or digest if you want upgrades to be explicit instead of following `latest`.

### TrueNAS Scale Custom App (`ix-apps` rendered compose)

If the running **`omnilux`** container was created by **Apps → Custom App** (not from a manual checkout of this repo), `docker compose` must use the **rendered** project file and project name from container labels — otherwise you get a **name conflict** (`/omnilux` already in use) when you run compose from `/repo` alone.

Discover labels (on the NAS):

```bash
sudo docker inspect omnilux --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}'
sudo docker inspect omnilux --format '{{index .Config.Labels "com.docker.compose.project"}}'
```

Then pull and recreate only the app service (example — replace paths with your `inspect` output):

```bash
COMPOSE_FILE="/mnt/.ix-apps/app_configs/omnilux/versions/1.0.0/templates/rendered/docker-compose.yaml"
COMPOSE_PROJECT="ix-omnilux"
sudo docker pull "${OMNILUX_IMAGE:-ghcr.io/omnilux-tv/omnilux:latest}"
sudo docker compose -f "$COMPOSE_FILE" -p "$COMPOSE_PROJECT" up -d omnilux --force-recreate
```

For repeat updates, keep the same inspected compose file and project name in your own host notes or automation. Do not edit the rendered TrueNAS compose file directly.

## 7. Related scripts

- `scripts/deploy.sh` — rsync this deploy repo to a remote host and pull/recreate (adjust `REMOTE`, `REMOTE_REPO_PATH`, `OMNILUX_IMAGE` in the environment as needed).
- `scripts/install.sh` — minimal local install under `~/.omnilux`.
