# Bare-metal Linux install contract

This is the official non-Docker Linux path for the OmniLux self-hosted runtime.

The installer consumes the published runtime image `ghcr.io/omnilux-tv/omnilux:latest`, extracts the built `/app` runtime directly from GHCR using the OCI Registry API, and installs it as a native `systemd` service. It does not require Docker and does not require source repository access.

## Support level

Supported today:

- Ubuntu 22.04, Ubuntu 24.04, Debian 12, or comparable Debian-family hosts
- `systemd`
- Node.js 22.x, installed by the installer when needed
- `ffmpeg` installed on the host
- SQLite runtime state in `/var/lib/omnilux`
- plugin state in `/var/lib/omnilux/plugins`
- media library root at `/srv/media`
- `systemd` service named `omnilux.service`
- public runtime image: `ghcr.io/omnilux-tv/omnilux:latest`

## Install

Once this repo is public, the no-auth install command is:

```bash
curl -fsSL https://raw.githubusercontent.com/omnilux-tv/omnilux-deploy/main/scripts/install/install-linux.sh \
  | sudo bash
```

From a checkout of this deploy repo:

```bash
sudo ./scripts/install/install-linux.sh
```

The installer:

1. Installs Ubuntu/Debian system dependencies.
2. Installs Node.js 22.x if needed.
3. Creates the `omnilux` system user and group.
4. Creates `/opt/omnilux`, `/etc/omnilux`, `/var/lib/omnilux`, `/var/lib/omnilux/plugins`, and `/srv/media`.
5. Downloads `ghcr.io/omnilux-tv/omnilux:latest` from GHCR without Docker.
6. Extracts the built `/app` runtime into `/opt/omnilux`.
7. Writes `/etc/omnilux/omnilux.env`.
8. Installs and starts `/etc/systemd/system/omnilux.service`.
9. Verifies `http://127.0.0.1:4000/api/health`.

## Useful overrides

```bash
curl -fsSL https://raw.githubusercontent.com/omnilux-tv/omnilux-deploy/main/scripts/install/install-linux.sh \
  | sudo OMNILUX_IMAGE=ghcr.io/omnilux-tv/omnilux:v0.1.0 \
      OMNILUX_MEDIA_DIR=/srv/media \
      OMNILUX_PUBLIC_ORIGIN=https://media.example.test \
      bash
```

Common options:

| Variable | Default | Purpose |
| --- | --- | --- |
| `OMNILUX_IMAGE` | `ghcr.io/omnilux-tv/omnilux:latest` | Runtime image tag or digest to install. |
| `OMNILUX_IMAGE_PLATFORM` | detected, usually `linux/amd64` | Image platform to extract. |
| `OMNILUX_APP_DIR` | `/opt/omnilux` | Extracted runtime directory. |
| `OMNILUX_CONFIG_DIR` | `/etc/omnilux` | Runtime environment and install metadata directory. |
| `OMNILUX_DATA_DIR` | `/var/lib/omnilux` | Database, downloads, logs, and local state. |
| `OMNILUX_PLUGINS_DIR` | `/var/lib/omnilux/plugins` | Installed plugin state. |
| `OMNILUX_MEDIA_DIR` | `/srv/media` | Host media library root. |
| `OMNILUX_PORT` | `4000` | HTTP port for UI and API. |
| `OMNILUX_PUBLIC_ORIGIN` | empty | External origin when reverse proxied. |
| `OMNILUX_SKIP_DEPENDENCIES` | `0` | Set `1` when apt dependencies are already managed. |
| `OMNILUX_SKIP_NODE_SETUP` | `0` | Set `1` to require an existing Node 22.x install. |
| `OMNILUX_START_SERVICE` | `1` | Set `0` to install files without starting. |

## Runtime environment

The installer preserves existing values in `/etc/omnilux/omnilux.env` and only appends missing defaults.

Important defaults:

```dotenv
NODE_ENV=production
PORT=4000
OMNILUX_DEPLOYMENT_PROFILE=self-hosted
OMNILUX_PRIMARY_DEPLOYMENT=bare-metal-linux
OMNILUX_DATA_DIR=/var/lib/omnilux
OMNILUX_DB_PATH=/var/lib/omnilux/omnilux.db
OMNILUX_LIBRARY_ROOT=/srv/media
OMNILUX_DOWNLOAD_PATH=/var/lib/omnilux/downloads
OMNILUX_PLUGINS_DIR=/var/lib/omnilux/plugins
OMNILUX_CLOUD_URL=https://api.omnilux.tv
OMNILUX_CLOUD_APP_URL=https://app.omnilux.tv
OMNILUX_RELAY_URL=wss://relay.omnilux.tv/ws/server
OMNILUX_BROWSER_SOLVER=auto
```

After editing the file:

```bash
sudo systemctl restart omnilux
```

## Operations

Health:

```bash
curl -fsS http://127.0.0.1:4000/api/health
systemctl status omnilux
```

Logs:

```bash
journalctl -u omnilux -f
```

Restart:

```bash
sudo systemctl restart omnilux
```

Upgrade in place:

```bash
curl -fsSL https://raw.githubusercontent.com/omnilux-tv/omnilux-deploy/main/scripts/install/install-linux.sh \
  | sudo OMNILUX_IMAGE=ghcr.io/omnilux-tv/omnilux:latest bash
```

Check an existing install:

```bash
sudo ./scripts/install/install-linux.sh check
```

The installer stores runtime metadata in `/etc/omnilux/install.json` and moves the previous runtime tree to `/opt/omnilux.previous` during replacement.

## Backup and rollback

Before upgrades:

```bash
sudo systemctl stop omnilux
sudo cp /var/lib/omnilux/omnilux.db "/var/lib/omnilux/omnilux.db.$(date +%Y%m%d%H%M%S).bak"
sudo systemctl start omnilux
```

Database migrations are forward-only. Rollback means restoring the previous database backup and moving `/opt/omnilux.previous` back to `/opt/omnilux`.

## Boundaries

This path is a native service install, not a source build and not a Docker Compose install. It still uses the same published runtime artifact as Docker so the runtime bits stay aligned across both self-hosted Linux paths.
