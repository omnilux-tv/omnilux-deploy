#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = (relativePath) => fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
const readJson = (relativePath) => JSON.parse(read(relativePath));

const contract = readJson('contracts/deploy-profile-contract.json');
const installContract = readJson('contracts/install-contract.json');
const envSchema = readJson('contracts/self-hosted-env-schema.json');
const errors = [];

if (contract.schemaVersion !== 1) {
  errors.push('schemaVersion must be 1');
}
if (contract.product !== installContract.product) {
  errors.push('deploy profile contract product must match install contract product');
}

const profileEnvVar = contract.profileEnvVar;
const primaryEnvVar = contract.primaryDeploymentEnvVar;
const envNames = new Set((envSchema.variables ?? []).map((variable) => variable.name));
for (const name of [profileEnvVar, primaryEnvVar]) {
  if (!envNames.has(name)) {
    errors.push(`${name} must be declared in contracts/self-hosted-env-schema.json`);
  }
  if (!installContract.environment.optional.includes(name)) {
    errors.push(`${name} must be optional env in contracts/install-contract.json`);
  }
}

const profiles = new Map();
for (const profile of contract.profiles ?? []) {
  if (!profile.id) {
    errors.push('profile id is required');
    continue;
  }
  profiles.set(profile.id, profile);
}
if (!profiles.has('self-hosted')) {
  errors.push('self-hosted profile is required');
}

const deployDocs = [
  read('README.md'),
  read('docs/self-hosted-setup.md'),
  read('docs/bare-metal-linux.md'),
  read('docs/bare-metal-macos.md'),
  read('docs/first-party-runtime-profiles.md'),
].join('\n');
const allDeployAssets = [
  read('scripts/install.sh'),
  read('scripts/install/install-linux.sh'),
  read('scripts/install/install-macos.sh'),
  read('docker/docker-compose.yml'),
  read('docker/docker-compose.example.yml'),
  read('docker-compose.truenas.yml'),
  read('env/example.env'),
  deployDocs,
].join('\n');

for (const deployment of contract.primaryDeployments ?? []) {
  if (!deployment.id || !deployment.profile || !deployment.mode) {
    errors.push('each primary deployment needs id, profile, and mode');
    continue;
  }
  if (!profiles.has(deployment.profile)) {
    errors.push(`${deployment.id} references unknown profile ${deployment.profile}`);
  }
  if (!Array.isArray(deployment.surfaces) || deployment.surfaces.length === 0) {
    errors.push(`${deployment.id} must declare projection surfaces`);
    continue;
  }
  for (const surface of deployment.surfaces) {
    const text = read(surface);
    if (!hasEnvName(text, profileEnvVar)) {
      errors.push(`${surface} must project ${profileEnvVar}`);
    }
    if (!text.includes(deployment.profile)) {
      errors.push(`${surface} must project profile value ${deployment.profile}`);
    }
    if (!hasEnvName(text, primaryEnvVar)) {
      errors.push(`${surface} must project ${primaryEnvVar}`);
    }
    if (!text.includes(deployment.id)) {
      errors.push(`${surface} must project primary deployment value ${deployment.id}`);
    }
  }
  if (!deployDocs.includes(deployment.id)) {
    errors.push(`deploy docs must mention primary deployment ${deployment.id}`);
  }
}

for (const value of ['managed-media', 'operator-console', 'first-party-managed']) {
  if (new RegExp(`${escapeRegExp(profileEnvVar)}[^\\n]*${escapeRegExp(value)}`).test(allDeployAssets)) {
    errors.push(`${profileEnvVar} must not use external profile value ${value} in omnilux-deploy`);
  }
  if (new RegExp(`${escapeRegExp(primaryEnvVar)}[^\\n]*${escapeRegExp(value)}`).test(allDeployAssets)) {
    errors.push(`${primaryEnvVar} must not use external primary deployment value ${value} in omnilux-deploy`);
  }
}

for (const owner of contract.externalOwners ?? []) {
  if (!deployDocs.includes(owner.repo) || !deployDocs.includes(owner.surface)) {
    errors.push(`deploy docs must route ${owner.id} to ${owner.repo} for ${owner.surface}`);
  }
}

if (errors.length > 0) {
  console.error('Deploy profile contract validation failed:');
  for (const error of errors) {
    console.error(`- ${error}`);
  }
  process.exit(1);
}

console.log('Deploy profile contract validation passed.');

function hasEnvName(text, name) {
  return new RegExp(`(^|[^A-Z0-9_])${escapeRegExp(name)}([^A-Z0-9_]|$)`, 'm').test(text);
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
