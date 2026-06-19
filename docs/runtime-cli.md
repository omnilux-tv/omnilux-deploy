# OmniLux runtime CLI

The `omnilux` command is the supported post-install management CLI for self-hosted OmniLux runtimes.

It is installed automatically by:

- `scripts/install.sh` for the minimal Docker install
- `scripts/install/install-linux.sh` for native Linux `systemd` installs
- `scripts/install/install-macos.sh` for native macOS `launchd` installs

## Commands

```bash
omnilux status
omnilux restart
omnilux services
omnilux plugins
omnilux auth
omnilux update
omnilux logs
omnilux media
omnilux connect
```

`omnilux help` prints the full command list and supported environment overrides. Unknown commands exit with a short usage guide and a human-readable error.

## Runtime status

```bash
omnilux status
```

Shows the detected runtime mode, service or container state, local runtime URL, health endpoint state, env file path, and install metadata when available.

The CLI detects these runtime modes:

- native Linux `systemd` service
- native macOS user `launchd` service
- Docker or Docker Compose container named `omnilux`

## Restart and services

```bash
omnilux restart
omnilux services
```

`restart` restarts the detected runtime and waits for `/api/health` to become reachable. On Linux it uses `systemctl`, on macOS it uses `launchctl`, and on Docker it uses Compose labels or falls back to `docker restart`.

`services` prints the native service status or Docker service/container details.

## Plugins

```bash
omnilux plugins
```

Shows installed plugin state from the runtime API when `OMNILUX_API_TOKEN` is set. If the API is unavailable or requires auth, the command falls back to the configured plugin directory.

## Authentication

```bash
omnilux auth
```

Shows whether first-run setup is still required and points the operator to the local setup URL when no admin account exists.

## Updates

```bash
omnilux update
omnilux update --check
omnilux update --run
```

Without `--run`, the command checks the runtime update API when available and then shows the detected local update path. `--check` is an explicit alias for the read-only check. With `--run`, it executes the supported update flow:

- Docker: pull and recreate the `omnilux` Compose service
- Linux: rerun the official native Linux installer in `upgrade` mode
- macOS: rerun the official native macOS installer in `upgrade` mode

The runtime API check is admin-protected. Set `OMNILUX_API_TOKEN` when you want `omnilux update` to include release availability and in-app updater state.

## Logs

```bash
omnilux logs
omnilux logs --tail 250
omnilux logs --follow
```

Shows recent runtime logs from `journalctl`, launchd log files, or Docker logs.

## Media

```bash
omnilux media
```

Shows the configured media root. If an admin API token is provided, it also shows library scan state.

## Cloud Connection

```bash
omnilux connect
```

Shows the configured OmniLux Cloud API URL, cloud app URL, relay URL, and public relay status when the runtime API is reachable.

## Authenticated API State

Some runtime API endpoints are admin-protected. Set `OMNILUX_API_TOKEN` when you need the CLI to read admin-only state:

```bash
OMNILUX_API_TOKEN=... omnilux plugins
OMNILUX_API_TOKEN=... omnilux media
```

Unauthenticated commands still return useful service, filesystem, and public health information.

## Overrides

Common overrides:

```bash
OMNILUX_RUNTIME_URL=http://127.0.0.1:4000
OMNILUX_ENV_FILE=/etc/omnilux/omnilux.env
OMNILUX_CONFIG_DIR=/etc/omnilux
OMNILUX_SERVICE_NAME=omnilux
OMNILUX_SERVICE_LABEL=tv.omnilux.server
OMNILUX_CONTAINER_NAME=omnilux
OMNILUX_COMPOSE_FILE=/path/to/docker-compose.yml
OMNILUX_COMPOSE_PROJECT=ix-omnilux
```

These are mainly for custom Docker layouts, test installs, or non-default native service names.
