#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = (relativePath) => fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
const readJson = (relativePath) => JSON.parse(read(relativePath));

const contract = readJson('contracts/updater-operation-contract.json');
const installContract = readJson('contracts/install-contract.json');
const envSchema = readJson('contracts/self-hosted-env-schema.json');
const compose = read('docker-compose.truenas.yml');
const server = read('updater/server.js');
const dockerfile = read('updater/Dockerfile');
const packageJson = read('updater/package.json');
const docs = [read('README.md'), read('docs/self-hosted-setup.md'), read('env/example.env')].join('\n');
const errors = [];

if (contract.schemaVersion !== 1) {
  errors.push('schemaVersion must be 1');
}
if (contract.product !== installContract.product) {
  errors.push('updater operation contract product must match install contract product');
}
if (contract.composeProfile !== installContract.security.updaterProfile) {
  errors.push('updater compose profile must match install contract security.updaterProfile');
}
if (contract.sidecar.dockerSocketMount !== installContract.security.updaterSocketMount) {
  errors.push('updater socket mount must match install contract security.updaterSocketMount');
}

const envNames = new Set((envSchema.variables ?? []).map((variable) => variable.name));
for (const [key, name] of Object.entries(contract.environment ?? {})) {
  if (!envNames.has(name)) {
    errors.push(`updater env ${key} (${name}) must be declared in self-hosted env schema`);
  }
}

requireIncludes('updater compose', compose, [
  `${contract.sidecar.service}:`,
  `profiles: ["${contract.composeProfile}"]`,
  'context: ./updater',
  `container_name: ${contract.sidecar.container}`,
  `OMNILUX_REPO_DIR: ${contract.sidecar.repoDir}`,
  'OMNILUX_COMPOSE_FILE: docker-compose.truenas.yml',
  'OMNILUX_IMAGE: ${OMNILUX_IMAGE:-ghcr.io/omnilux-tv/omnilux:latest}',
  'OMNILUX_UPDATER_TOKEN: ${OMNILUX_UPDATER_TOKEN:-}',
  'OMNILUX_HEALTH_URL: ${OMNILUX_HEALTH_URL:-http://omnilux:4000/api/health}',
  `${contract.sidecar.dockerSocketMount}:${contract.sidecar.dockerSocketMount}`,
  `${contract.sidecar.dockerCredentialsMount}:${contract.sidecar.dockerCredentialsMount}:ro`,
  'no-new-privileges:true',
  'http://127.0.0.1:4050/healthz',
]);

requireIncludes('updater server', server, [
  "process.env.OMNILUX_REPO_DIR || '/repo'",
  "process.env.OMNILUX_COMPOSE_FILE || 'docker-compose.truenas.yml'",
  "process.env.OMNILUX_IMAGE || 'ghcr.io/omnilux-tv/omnilux:latest'",
  "process.env.OMNILUX_UPDATER_TOKEN",
  "process.env.OMNILUX_HEALTH_URL || 'http://omnilux:4000/api/health'",
  'process.env.OMNILUX_HEALTH_TIMEOUT_MS || 120000',
  'process.env.OMNILUX_HEALTH_INTERVAL_MS || 3000',
  'req.headers.authorization === `Bearer ${token}`',
  "token ? 401 : 503",
  "error: token ? 'Unauthorized' : 'Updater token is not configured.'",
  "req.method === 'GET' && req.url === '/healthz'",
  "req.method === 'GET' && req.url === '/status'",
  "req.method === 'POST' && req.url === '/update'",
  "send(res, 409, { error: 'Update already running', ...state })",
  "state: 'idle'",
  "state.state = 'running'",
  "state.state = 'succeeded'",
  "state.state = 'failed'",
  "['compose', '-f', composeFile, 'pull', 'omnilux']",
  "['compose', '-f', composeFile, 'up', '-d', '--force-recreate', 'omnilux']",
  'await waitForRuntimeHealth()',
  'state.log.length > 80',
]);

requireIncludes('updater runtime package', dockerfile + packageJson, [
  'FROM docker:28-cli',
  'apk add --no-cache nodejs',
  '"type": "module"',
  '"start": "node server.js"',
]);

requireIncludes('updater docs', docs, [
  'COMPOSE_PROFILES=updater',
  'OMNILUX_UPDATER_URL=http://omnilux-updater:4050',
  'OMNILUX_UPDATER_TOKEN',
  'OMNILUX_HEALTH_URL',
  'OMNILUX_HEALTH_TIMEOUT_MS',
  'OMNILUX_HEALTH_INTERVAL_MS',
  '/var/run/docker.sock',
  'Leaving `OMNILUX_UPDATER_TOKEN` unset disables the updater control API',
]);

if (errors.length > 0) {
  console.error('Updater operation validation failed:');
  for (const error of errors) {
    console.error(`- ${error}`);
  }
  process.exit(1);
}

console.log('Updater operation validation passed.');

function requireIncludes(label, text, snippets) {
  for (const snippet of snippets) {
    if (!text.includes(snippet)) {
      errors.push(`${label} is missing: ${snippet}`);
    }
  }
}
