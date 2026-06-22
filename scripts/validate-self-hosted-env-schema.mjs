#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = (relativePath) => fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
const readJson = (relativePath) => JSON.parse(read(relativePath));

const schema = readJson('contracts/self-hosted-env-schema.json');
const installContract = readJson('contracts/install-contract.json');
const errors = [];

const knownPlatforms = new Set(schema.platforms ?? []);
const knownScopes = new Set(schema.scopes ?? []);
const variables = Array.isArray(schema.variables) ? schema.variables : [];
const byName = new Map();

if (schema.schemaVersion !== 1) {
  errors.push('schemaVersion must be 1');
}
if (schema.product !== installContract.product) {
  errors.push('self-hosted env schema product must match install contract product');
}

for (const variable of variables) {
  if (!variable || typeof variable.name !== 'string' || !variable.name) {
    errors.push('each variable needs a non-empty name');
    continue;
  }
  if (byName.has(variable.name)) {
    errors.push(`duplicate variable: ${variable.name}`);
  }
  byName.set(variable.name, variable);
  if (!Array.isArray(variable.scopes) || variable.scopes.length === 0) {
    errors.push(`${variable.name} must declare at least one scope`);
  }
  if (!Array.isArray(variable.platforms) || variable.platforms.length === 0) {
    errors.push(`${variable.name} must declare at least one platform`);
  }
  for (const scope of variable.scopes ?? []) {
    if (!knownScopes.has(scope)) errors.push(`${variable.name} uses unknown scope ${scope}`);
  }
  for (const platform of variable.platforms ?? []) {
    if (!knownPlatforms.has(platform)) errors.push(`${variable.name} uses unknown platform ${platform}`);
  }
  if (variable.sensitive && typeof variable.default === 'string' && variable.default && !['auto', 'detected'].includes(variable.default)) {
    errors.push(`${variable.name} is sensitive and must not define a non-empty default`);
  }
}

const composeTexts = [
  'docker/docker-compose.yml',
  'docker/docker-compose.example.yml',
  'docker-compose.truenas.yml',
  'docker-compose.truenas.local-build.yml',
  'docker-compose.truenas-ix-image-local.yml',
].map((relativePath) => [relativePath, read(relativePath)]);

const linuxInstaller = read('scripts/install/install-linux.sh');
const macosInstaller = read('scripts/install/install-macos.sh');
const dockerInstaller = read('scripts/install.sh');
const updaterServer = read('updater/server.js');
const cli = read('scripts/omnilux');
const envTemplate = read('env/example.env');
const deployDocs = [
  read('README.md'),
  read('docs/self-hosted-setup.md'),
  read('docs/bare-metal-linux.md'),
  read('docs/bare-metal-macos.md'),
  read('docs/runtime-cli.md'),
].join('\n');

const observed = new Set();
for (const [, text] of composeTexts) {
  for (const name of collectComposeSubstitutions(text)) observed.add(name);
}
for (const text of [linuxInstaller, macosInstaller, dockerInstaller]) {
  for (const name of collectInstallerInputs(text)) observed.add(name);
  for (const name of collectNativeEnvDefaults(text)) observed.add(name);
}
for (const name of collectProcessEnv(updaterServer)) observed.add(name);
for (const name of collectCliUsage(cli)) observed.add(name);

for (const name of observed) {
  if (!byName.has(name)) {
    errors.push(`observed supported env ${name} is missing from contracts/self-hosted-env-schema.json`);
  }
}

const contractEnv = [
  installContract.image?.envVar,
  ...(installContract.environment?.required ?? []),
  ...(installContract.environment?.installerDefaults ?? []),
  ...(installContract.environment?.optional ?? []),
].filter(Boolean);
for (const name of contractEnv) {
  if (!byName.has(name)) {
    errors.push(`install contract env ${name} is missing from self-hosted env schema`);
  }
}

for (const variable of variables) {
  const name = variable.name;
  const sourceText = [envTemplate, ...composeTexts.map(([, text]) => text), linuxInstaller, macosInstaller, dockerInstaller, cli, deployDocs].join('\n');
  if (!hasEnvName(sourceText, name)) {
    errors.push(`${name} is declared in schema but not projected by deploy assets or docs`);
  }
  if (variable.scopes?.includes('env-template') && !hasEnvName(envTemplate, name)) {
    errors.push(`${name} is marked env-template but missing from env/example.env`);
  }
  if (variable.scopes?.includes('native-env-file')) {
    if (!hasAppendDefault(linuxInstaller, name) && !hasAppendDefault(macosInstaller, name)) {
      errors.push(`${name} is marked native-env-file but is not written by native installers`);
    }
    if (!hasEnvName(deployDocs, name)) {
      errors.push(`${name} is marked native-env-file but missing from deploy docs`);
    }
  }
  if (variable.scopes?.includes('cli-override') && !hasEnvName(cli, name)) {
    errors.push(`${name} is marked cli-override but missing from scripts/omnilux`);
  }
}

if (errors.length > 0) {
  console.error('Self-hosted env schema validation failed:');
  for (const error of errors) {
    console.error(`- ${error}`);
  }
  process.exit(1);
}

console.log('Self-hosted env schema validation passed.');

function collectComposeSubstitutions(text) {
  return collectNames(text, /\$\{([A-Z0-9_]+)(?::[-?][^}]*)?\}/g);
}

function collectInstallerInputs(text) {
  const names = new Set();
  for (const name of collectNames(text, /^([A-Z0-9_]+)="\$\{[A-Z0-9_]+(?::-[^}]*)?\}"/gm)) {
    if (isSupportedEnvName(name)) names.add(name);
  }
  return names;
}

function collectNativeEnvDefaults(text) {
  return collectNames(text, /append_env_default\s+"([A-Z0-9_]+)"/g);
}

function collectCliUsage(text) {
  const environmentStart = text.indexOf('Environment:');
  const environmentEnd = text.indexOf('EOF', environmentStart);
  if (environmentStart === -1 || environmentEnd === -1) return new Set();
  return collectNames(text.slice(environmentStart, environmentEnd), /^\s{2}([A-Z0-9_]+)\s+/gm);
}

function collectProcessEnv(text) {
  return collectNames(text, /process\.env\.([A-Z0-9_]+)/g);
}

function collectNames(text, regex) {
  const names = new Set();
  for (const match of text.matchAll(regex)) {
    if (isSupportedEnvName(match[1])) names.add(match[1]);
  }
  return names;
}

function isSupportedEnvName(name) {
  return (
    name.startsWith('OMNILUX_') ||
    name.startsWith('SUPABASE_') ||
    ['COMPOSE_PROFILES', 'GHCR_TOKEN', 'LIBRARY_ROOT', 'LOG_LEVEL', 'NODE_ENV', 'NODE_MAJOR', 'PORT', 'TMDB_API_KEY'].includes(name)
  );
}

function hasEnvName(text, name) {
  return new RegExp(`(^|[^A-Z0-9_])${escapeRegExp(name)}([^A-Z0-9_]|$)`, 'm').test(text);
}

function hasAppendDefault(text, name) {
  return text.includes(`append_env_default "${name}"`);
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
