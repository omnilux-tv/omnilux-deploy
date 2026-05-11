# Self-hosted OmniLux server setup

Universal steps for any Docker host. Official compose contracts live in this repo; **host-specific paths and secrets** belong in a private repo (for example `omnilux-infra`), not here.

## 1. What you run

- **Published image:** `ghcr.io/omnilux-tv/omnilux` (tags such as `latest` or a release tag). Built from `omnilux` via [docker-publish workflow](https://github.com/omnilux-tv/omnilux/blob/main/.github/workflows/docker-publish.yml) on pushes to `main` and version tags.
- **Compose:** use `docker-compose.truenas.yml` for GPU / DLNA / updater sidecar patterns, or `scripts/install.sh` for a minimal single-container layout under `~/.omnilux`.

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

## 4. Bring the stack up

From the directory that contains your compose file (and `updater/` if you use `omnilux-updater`):

```bash
docker login ghcr.io   # if required (see §2)
docker compose -f docker-compose.truenas.yml pull omnilux omnilux-updater
docker compose -f docker-compose.truenas.yml up -d --build
```

Health: `GET http://<host>:<mapped-port>/api/health` (default TrueNAS mapping in the contract file is `38400:4000`).

## 5. Stay on a current image

After registry access works:

```bash
docker compose -f docker-compose.truenas.yml pull omnilux
docker compose -f docker-compose.truenas.yml up -d omnilux omnilux-updater
```

Pin **`OMNILUX_IMAGE`** to a specific tag or digest if you want upgrades to be explicit instead of following `latest`.

## 6. Related scripts

- `scripts/deploy.sh` — rsync this deploy repo to a remote host and pull/recreate (adjust `REMOTE`, `REMOTE_REPO_PATH`, `OMNILUX_IMAGE` in the environment as needed).
- `scripts/install.sh` — minimal local install under `~/.omnilux`.
