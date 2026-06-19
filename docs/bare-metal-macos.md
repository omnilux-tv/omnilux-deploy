# Bare-metal macOS install contract

This is the official non-Docker macOS path for the OmniLux self-hosted runtime.

The installer consumes a Darwin-built runtime tarball such as `omnilux-darwin-arm64.tar.gz` or `omnilux-darwin-x64.tar.gz`, installs the runtime under the current user's Library directory, installs `OmniLux.app` into `/Applications`, and runs the runtime as a user-level `launchd` service. It does not require Docker and does not require source repository access.

## Support level

Supported today:

- macOS 13 or newer
- Apple Silicon (`arm64`) and Intel (`x64`) artifact names
- Node.js 22.x on the host
- `ffmpeg` installed on the host
- SQLite runtime state in `~/Library/Application Support/OmniLux/data`
- plugin state in `~/Library/Application Support/OmniLux/plugins`
- media library root at `~/Movies/OmniLux`
- recognizable app bundle at `/Applications/OmniLux.app`
- user LaunchAgent named `tv.omnilux.server`
- menu bar helper LaunchAgent named `tv.omnilux.menubar`

Published release assets:

- `omnilux-darwin-arm64.tar.gz`
- `omnilux-darwin-x64.tar.gz`

## Install

The no-auth install command is:

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
9. Installs `OmniLux.app` into `/Applications`.
10. Installs the `omnilux` management CLI.
11. Installs and starts the OmniLux menu bar helper through the app bundle.
12. Verifies `http://127.0.0.1:4000/api/health`.

## Useful overrides

Use a specific artifact URL:

```bash
curl -fsSL https://raw.githubusercontent.com/omnilux-tv/omnilux-deploy/main/scripts/install/install-macos.sh \
  | OMNILUX_ARTIFACT_URL=https://github.com/omnilux-tv/omnilux/releases/download/v0.1.0/omnilux-darwin-arm64.tar.gz \
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
| `OMNILUX_CLI_PATH` | `~/.local/bin/omnilux` | Installed runtime management CLI path. |
| `OMNILUX_APPLICATIONS_DIR` | `/Applications` | Destination for `OmniLux.app`. Use a test-only override with `OMNILUX_INSTALL_ROOT`. |
| `OMNILUX_NODE_BIN` | auto | Path to Node.js 22.x. |
| `OMNILUX_PORT` | `4000` | HTTP port for UI and API. |
| `OMNILUX_PUBLIC_ORIGIN` | empty | External origin when reverse proxied. |
| `OMNILUX_MENU_BAR_LABEL` | `tv.omnilux.menubar` | User LaunchAgent label for the menu bar helper. |
| `OMNILUX_SKIP_DEPENDENCIES` | `0` | Set `1` when Homebrew dependencies are already managed. |
| `OMNILUX_SKIP_NODE_SETUP` | `0` | Set `1` to require an existing Node 22.x install. |
| `OMNILUX_START_SERVICE` | `1` | Set `0` to install files without starting. |
| `OMNILUX_START_MENU_BAR` | same as `OMNILUX_START_SERVICE` | Set `0` to install the menu bar helper without starting it. |

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

## OmniLux app and menu bar

Darwin runtime artifacts include `OmniLux.app`. The installer copies it to `/Applications/OmniLux.app` with the OmniLux name and icon. The app runs without a Dock icon and starts through `~/Library/LaunchAgents/tv.omnilux.menubar.plist` for the menu bar experience.

Opening `OmniLux.app` from Applications starts the runtime if needed and opens the local dashboard. When launchd starts the same app at login, it stays in the menu bar and does not open the dashboard automatically.

The menu shows:

- current runtime status and local connection state
- a compact dashboard panel with launchd and health-check status
- open dashboard and settings
- start, stop, and restart runtime
- reveal logs
- run the native macOS update path
- quit the menu bar helper

The helper checks `http://127.0.0.1:4000/api/health` by default and uses launchd to manage `tv.omnilux.server`. Its states are:

- `Running`: the local health endpoint is reachable
- `Stopped`: launchd is not running the runtime and health is unreachable
- `Disconnected`: launchd has the runtime loaded, but the local health endpoint is not answering
- `Updating`: a start, stop, restart, or update action is in progress

Start or restart the helper manually:

```bash
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/tv.omnilux.menubar.plist"
launchctl kickstart -k "gui/$(id -u)/tv.omnilux.menubar"
```

## Developer build

Build Darwin runtime artifacts from the `omnilux/` repo on macOS:

```bash
cd ../omnilux
pnpm install
./scripts/package-darwin-runtime.sh
```

Requirements:

- macOS 13 or newer
- Node.js 22.x
- pnpm 10.32.1
- Xcode command line tools with `swiftc`, `iconutil`, and `ditto`

The script builds the server/web runtime, compiles `apps/macos-menubar` into `OmniLux.app`, generates `OmniLux.icns`, verifies the runtime tree, and writes `dist/artifacts/omnilux-darwin-arm64.tar.gz` or `dist/artifacts/omnilux-darwin-x64.tar.gz`.

Install a local build from the deploy repo:

```bash
OMNILUX_ARTIFACT_FILE=../omnilux/dist/artifacts/omnilux-darwin-arm64.tar.gz \
./scripts/install/install-macos.sh
```

## Operations

Health:

```bash
omnilux status
curl -fsS http://127.0.0.1:4000/api/health
launchctl print "gui/$(id -u)/tv.omnilux.server"
```

Logs:

```bash
omnilux logs --follow
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
omnilux update --run
curl -fsSL https://raw.githubusercontent.com/omnilux-tv/omnilux-deploy/main/scripts/install/install-macos.sh \
  | OMNILUX_ARTIFACT_URL=https://github.com/omnilux-tv/omnilux/releases/latest/download/omnilux-darwin-arm64.tar.gz \
    bash
```

See [`runtime-cli.md`](runtime-cli.md) for all runtime management commands.

The installer stores runtime metadata in `~/Library/Application Support/OmniLux/install.json` and moves the previous runtime tree to `~/Library/Application Support/OmniLux/runtime.previous` during replacement.

## Uninstall

Stop launchd jobs and remove the installed app:

```bash
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/tv.omnilux.menubar.plist" 2>/dev/null || true
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/tv.omnilux.server.plist" 2>/dev/null || true
rm -rf "/Applications/OmniLux.app"
rm -f "$HOME/Library/LaunchAgents/tv.omnilux.menubar.plist"
rm -f "$HOME/Library/LaunchAgents/tv.omnilux.server.plist"
```

Remove runtime state only when you also want to delete the local database, plugins, downloads, logs, and library defaults:

```bash
rm -rf "$HOME/Library/Application Support/OmniLux"
rm -rf "$HOME/Movies/OmniLux"
rm -f "$HOME/.local/bin/omnilux"
```

## Boundaries

This path is a native macOS service install, not a source build and not a Docker Compose install. The runtime artifact must be built on macOS for the target architecture because native Node modules cannot be reused from the Linux image.
