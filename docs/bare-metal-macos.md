# Bare-metal macOS install contract

This is the official non-Docker macOS path for the OmniLux self-hosted runtime.

The installer consumes a Darwin-built runtime tarball such as `omnilux-darwin-arm64.tar.gz` or `omnilux-darwin-x64.tar.gz`, installs it under the current user's Library directory, and runs it as a user-level `launchd` service. It does not require Docker and does not require source repository access.

## Support level

Supported today:

- macOS 13 or newer
- Apple Silicon (`arm64`) and Intel (`x64`) artifact names
- Node.js 22.x on the host
- `ffmpeg` installed on the host
- SQLite runtime state in `~/Library/Application Support/OmniLux/data`
- plugin state in `~/Library/Application Support/OmniLux/plugins`
- media library root at `~/Movies/OmniLux`
- user LaunchAgent named `tv.omnilux.server`

Required before public customer use:

- publish the Darwin runtime tarballs as public release assets:
  - `omnilux-darwin-arm64.tar.gz`
  - `omnilux-darwin-x64.tar.gz`

## Install

Once the release assets exist, the no-auth install command is:

```bash
curl -fsSL https://raw.githubusercontent.com/omnilux-tv/omnilux-deploy/main/scripts/install/install-macos.sh \
  | bash
```

Do not run this installer with `sudo`. It installs a user-level LaunchAgent, not a root LaunchDaemon.

From a checkout of this deploy repo:

```bash
./scripts/install/install-macos.sh
```

The installer:

1. Verifies macOS and CPU architecture.
2. Verifies or installs Node.js 22.x.
3. Verifies or installs `ffmpeg`.
4. Creates the user-level OmniLux runtime directories.
5. Downloads the Darwin runtime tarball or uses `OMNILUX_ARTIFACT_FILE`.
6. Extracts the built runtime into `~/Library/Application Support/OmniLux/runtime`.
7. Writes `~/Library/Application Support/OmniLux/omnilux.env`.
8. Installs and starts `~/Library/LaunchAgents/tv.omnilux.server.plist`.
9. Verifies `http://127.0.0.1:4000/api/health`.

## Useful overrides

Use a specific artifact URL:

```bash
curl -fsSL https://raw.githubusercontent.com/omnilux-tv/omnilux-deploy/main/scripts/install/install-macos.sh \
  | OMNILUX_ARTIFACT_URL=https://github.com/omnilux-tv/omnilux-deploy/releases/download/v0.1.0/omnilux-darwin-arm64.tar.gz \
    bash
```

Install from a local artifact without starting launchd:

```bash
OMNILUX_ARTIFACT_FILE=/tmp/omnilux-darwin-arm64.tar.gz \
OMNILUX_START_SERVICE=0 \
./scripts/install/install-macos.sh
```

Sandbox the file layout for installer testing:

```bash
tmp_root="$(mktemp -d)"
OMNILUX_ARTIFACT_FILE=/tmp/omnilux-darwin-arm64.tar.gz \
OMNILUX_INSTALL_ROOT="${tmp_root}" \
OMNILUX_START_SERVICE=0 \
OMNILUX_SKIP_DEPENDENCIES=1 \
./scripts/install/install-macos.sh
```

Common options:

| Variable | Default | Purpose |
| --- | --- | --- |
| `OMNILUX_ARTIFACT_URL` | latest public release asset for host arch | Runtime tarball URL. |
| `OMNILUX_ARTIFACT_FILE` | empty | Local runtime tarball path for testing or offline installs. |
| `OMNILUX_ARCH` | detected, `arm64` or `x64` | Artifact architecture selector. |
| `OMNILUX_INSTALL_ROOT` | empty | Test-only prefix that prevents writes to the real user Library paths. |
| `OMNILUX_APP_DIR` | `~/Library/Application Support/OmniLux/runtime` | Extracted runtime directory. |
| `OMNILUX_CONFIG_DIR` | `~/Library/Application Support/OmniLux` | Runtime environment and install metadata directory. |
| `OMNILUX_DATA_DIR` | `~/Library/Application Support/OmniLux/data` | Database, downloads, logs, and local state. |
| `OMNILUX_PLUGINS_DIR` | `~/Library/Application Support/OmniLux/plugins` | Installed plugin state. |
| `OMNILUX_MEDIA_DIR` | `~/Movies/OmniLux` | Host media library root. |
| `OMNILUX_NODE_BIN` | auto | Path to Node.js 22.x. |
| `OMNILUX_PORT` | `4000` | HTTP port for UI and API. |
| `OMNILUX_PUBLIC_ORIGIN` | empty | External origin when reverse proxied. |
| `OMNILUX_SKIP_DEPENDENCIES` | `0` | Set `1` when Homebrew dependencies are already managed. |
| `OMNILUX_SKIP_NODE_SETUP` | `0` | Set `1` to require an existing Node 22.x install. |
| `OMNILUX_START_SERVICE` | `1` | Set `0` to install files without starting. |

## Runtime environment

Important defaults in `~/Library/Application Support/OmniLux/omnilux.env`:

```dotenv
NODE_ENV=production
PORT=4000
OMNILUX_DEPLOYMENT_PROFILE=self-hosted
OMNILUX_PRIMARY_DEPLOYMENT=bare-metal-macos
OMNILUX_DATA_DIR=/Users/you/Library/Application\ Support/OmniLux/data
OMNILUX_DB_PATH=/Users/you/Library/Application\ Support/OmniLux/data/omnilux.db
OMNILUX_LIBRARY_ROOT=/Users/you/Movies/OmniLux
OMNILUX_DOWNLOAD_PATH=/Users/you/Library/Application\ Support/OmniLux/data/downloads
OMNILUX_PLUGINS_DIR=/Users/you/Library/Application\ Support/OmniLux/plugins
OMNILUX_CLOUD_URL=https://api.omnilux.tv
OMNILUX_CLOUD_APP_URL=https://app.omnilux.tv
OMNILUX_RELAY_URL=wss://relay.omnilux.tv/ws/server
OMNILUX_BROWSER_SOLVER=auto
```

After editing the file:

```bash
launchctl kickstart -k "gui/$(id -u)/tv.omnilux.server"
```

## Operations

Health:

```bash
curl -fsS http://127.0.0.1:4000/api/health
launchctl print "gui/$(id -u)/tv.omnilux.server"
```

Logs:

```bash
tail -f "$HOME/Library/Application Support/OmniLux/data/logs/omnilux.err.log"
tail -f "$HOME/Library/Application Support/OmniLux/data/logs/omnilux.out.log"
```

Stop:

```bash
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/tv.omnilux.server.plist"
```

Start:

```bash
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/tv.omnilux.server.plist"
launchctl kickstart -k "gui/$(id -u)/tv.omnilux.server"
```

Upgrade in place:

```bash
curl -fsSL https://raw.githubusercontent.com/omnilux-tv/omnilux-deploy/main/scripts/install/install-macos.sh \
  | OMNILUX_ARTIFACT_URL=https://github.com/omnilux-tv/omnilux-deploy/releases/latest/download/omnilux-darwin-arm64.tar.gz \
    bash
```

The installer stores runtime metadata in `~/Library/Application Support/OmniLux/install.json` and moves the previous runtime tree to `~/Library/Application Support/OmniLux/runtime.previous` during replacement.

## Boundaries

This path is a native macOS service install, not a source build and not a Docker Compose install. The runtime artifact must be built on macOS for the target architecture because native Node modules cannot be reused from the Linux image.
