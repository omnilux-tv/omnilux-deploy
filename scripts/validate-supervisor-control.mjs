#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

const read = (relativePath) => fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');

const cli = read('scripts/omnilux');
const docs = read('docs/runtime-cli.md');
const dockerInstall = read('scripts/install.sh');
const linuxInstall = read('scripts/install/install-linux.sh');
const macosInstall = read('scripts/install/install-macos.sh');

const errors = [];

function requireIncludes(label, text, snippets) {
  for (const snippet of snippets) {
    if (!text.includes(snippet)) {
      errors.push(`${label} is missing: ${snippet}`);
    }
  }
}

function requireRegex(label, text, regex) {
  if (!regex.test(text)) {
    errors.push(`${label} does not match ${regex}`);
  }
}

requireIncludes('CLI usage', cli, [
  'status      Show runtime, service, install, and health status',
  'restart     Restart the OmniLux runtime service or container',
  'services    Show native service or Docker service details',
  'plugins     Show installed plugin state and plugin directory',
  'auth        Show local setup/auth readiness',
  'update      Show or run the supported runtime update path',
  'logs        Show recent runtime logs',
  'media       Show media library and scan state',
  'connect     Show OmniLux Cloud and relay connection state',
  'OMNILUX_RUNTIME_URL',
  'OMNILUX_API_TOKEN',
  'OMNILUX_ENV_FILE',
  'OMNILUX_CONFIG_DIR',
  'OMNILUX_SERVICE_NAME',
  'OMNILUX_SERVICE_LABEL',
  'OMNILUX_CONTAINER_NAME',
  'OMNILUX_COMPOSE_SERVICE',
  'OMNILUX_COMPOSE_FILE',
  'OMNILUX_COMPOSE_PROJECT',
]);

requireIncludes('runtime mode detection', cli, [
  'systemd_available()',
  'launchd_available()',
  'docker_available()',
  "printf 'systemd'",
  "printf 'launchd'",
  "printf 'docker'",
  "printf 'unknown'",
]);

requireIncludes('Docker Compose Adapter', cli, [
  'compose_args_from_container()',
  'docker_compose_command()',
  'run_compose()',
  'com.docker.compose.project.config_files',
  'com.docker.compose.project',
  'docker compose version',
  'docker-compose',
]);

requireIncludes('status projection', cli, [
  'command_status()',
  "printf 'Mode: %s\\n'",
  "printf 'Runtime URL: %s\\n'",
  "printf 'Env file: %s%s\\n'",
  "printf 'Health: reachable\\n'",
  "printf 'Health: unavailable'",
  'metadata_summary',
  'Install metadata:',
  "'image', 'artifact', 'platform', 'arch', 'manifest', 'revision', 'installedAt', 'runtimeDir', 'previousRuntimeDir'",
]);

requireIncludes('restart operation', cli, [
  'command_restart()',
  'systemctl restart "${SERVICE_NAME}.service"',
  'launchctl bootout "$(launchd_domain)" "$(launchd_plist)"',
  'launchctl bootstrap "$(launchd_domain)" "$(launchd_plist)"',
  'launchctl kickstart -k "$(launchd_domain)/${SERVICE_LABEL}"',
  'run_compose restart "${COMPOSE_SERVICE}"',
  'docker restart "${CONTAINER_NAME}"',
  'wait_for_health || exit 1',
]);

requireIncludes('update operation', cli, [
  'command_update()',
  'print_update_api_status',
  "printf 'Docker install detected.\\n'",
  'run_compose pull "${COMPOSE_SERVICE}"',
  'run_compose up -d --force-recreate "${COMPOSE_SERVICE}"',
  'OMNILUX_LINUX_INSTALLER_URL',
  'install-linux.sh',
  'OMNILUX_MACOS_INSTALLER_URL',
  'install-macos.sh',
  'bash -s -- upgrade',
]);

requireIncludes('log operation', cli, [
  'command_logs()',
  'journalctl',
  'OMNILUX_OUT_LOG',
  'OMNILUX_ERR_LOG',
  'tail -n "${tail_lines}"',
  'run_compose logs',
  'docker logs',
]);

requireIncludes('runtime state commands', cli, [
  'command_services()',
  'command_plugins()',
  'command_auth()',
  'command_media()',
  'command_connect()',
  '/api/plugins',
  '/api/auth/setup-status',
  '/api/library/scan/status',
  '/api/server/relay-status',
]);

requireRegex('main command dispatch', cli, /case "\$\{command\}" in[\s\S]*status\)[\s\S]*command_status[\s\S]*restart\)[\s\S]*command_restart[\s\S]*services\)[\s\S]*command_services[\s\S]*plugins\)[\s\S]*command_plugins[\s\S]*auth\)[\s\S]*command_auth[\s\S]*update\)[\s\S]*command_update[\s\S]*logs\)[\s\S]*command_logs[\s\S]*media\)[\s\S]*command_media[\s\S]*connect\)[\s\S]*command_connect/);

requireIncludes('runtime CLI docs', docs, [
  'The `omnilux` command is the supported post-install management CLI',
  'scripts/install.sh',
  'scripts/install/install-linux.sh',
  'scripts/install/install-macos.sh',
  'omnilux status',
  'omnilux restart',
  'omnilux services',
  'omnilux plugins',
  'omnilux auth',
  'omnilux update',
  'omnilux logs',
  'omnilux media',
  'omnilux connect',
  'native Linux `systemd` service',
  'native macOS user `launchd` service',
  'Docker or Docker Compose container named `omnilux`',
  'waits for `/api/health`',
  'Compose labels or falls back to `docker restart`',
  '`journalctl`',
  'launchd log files',
  'Docker logs',
  'OMNILUX_RUNTIME_URL',
  'OMNILUX_COMPOSE_PROJECT',
]);

requireIncludes('Docker installer CLI installation', dockerInstall, [
  'CLI_URL="${OMNILUX_CLI_URL:-https://raw.githubusercontent.com/omnilux-tv/omnilux-deploy/main/scripts/omnilux}"',
  'install_cli()',
  'install_cli',
  'omnilux update --run',
]);

requireIncludes('Linux installer CLI installation', linuxInstall, [
  'OMNILUX_CLI_URL="${OMNILUX_CLI_URL:-https://raw.githubusercontent.com/omnilux-tv/omnilux-deploy/main/scripts/omnilux}"',
  'install_cli()',
  'write_systemd_service',
  'install_cli',
]);

requireIncludes('macOS installer CLI installation', macosInstall, [
  'OMNILUX_CLI_URL="${OMNILUX_CLI_URL:-https://raw.githubusercontent.com/omnilux-tv/omnilux-deploy/main/scripts/omnilux}"',
  'install_cli()',
  'launchctl bootstrap',
  'install_cli',
]);

if (errors.length > 0) {
  console.error('Supervisor control validation failed:');
  for (const error of errors) {
    console.error(`- ${error}`);
  }
  process.exit(1);
}

console.log('Supervisor control validation passed.');
