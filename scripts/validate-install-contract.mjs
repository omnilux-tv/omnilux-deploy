#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(fileURLToPath(new URL("..", import.meta.url)));
const contractPath = resolve(root, "contracts/install-contract.json");
const contract = readJson(contractPath);
const errors = [];

requireString(contract.product, "product");
requireString(contract.image?.envVar, "image.envVar");
requireString(contract.image?.default, "image.default");
requireArray(contract.platforms, "platforms");
requireArray(contract.environment?.required, "environment.required", { allowEmpty: true });
requireArray(contract.environment?.installerDefaults, "environment.installerDefaults");
requireArray(contract.environment?.optional, "environment.optional");
requireArray(contract.volumes, "volumes");
requireString(contract.security?.requiredSecurityOpt, "security.requiredSecurityOpt");
requireString(contract.healthcheck?.path, "healthcheck.path");

for (const platform of contract.platforms ?? []) {
  const entrypoint = platform?.entrypoint;
  if (typeof entrypoint !== "string" || !entrypoint) {
    errors.push("platform entrypoint is required");
    continue;
  }
  readText(entrypoint);
}

const envTemplate = readText("env/example.env");
for (const envName of contract.environment?.required ?? []) {
  if (!hasEnvName(envTemplate, envName)) {
    errors.push(`env/example.env is missing required env ${envName}`);
  }
}

const deployTexts = [
  "scripts/install.sh",
  "scripts/install/install-linux.sh",
  "scripts/install/install-macos.sh",
  "docker/docker-compose.yml",
  "docker/docker-compose.example.yml",
  "docker-compose.truenas.yml",
].map((path) => [path, readText(path)]);

const contractTerms = [
  contract.image.envVar,
  contract.image.default,
  contract.security.requiredSecurityOpt,
  contract.security.updaterProfile,
  contract.security.updaterSocketMount,
  contract.healthcheck.path,
  ...contract.volumes.flatMap((volume) => [volume.name, volume.target]),
].filter((value) => typeof value === "string" && value.length > 0);

for (const term of contractTerms) {
  if (!deployTexts.some(([, text]) => text.includes(term))) {
    errors.push(`contract term ${term} is not projected by deploy assets`);
  }
}

for (const envName of [
  ...contract.environment.required,
  ...contract.environment.installerDefaults,
  ...contract.environment.optional,
]) {
  if (!deployTexts.some(([, text]) => text.includes(envName)) && !hasEnvName(envTemplate, envName)) {
    errors.push(`env ${envName} is not projected by env template or deploy assets`);
  }
}

const containerSecurityOptAssets = [
  "scripts/install.sh",
  "docker/docker-compose.yml",
  "docker/docker-compose.example.yml",
  "docker-compose.truenas.yml",
];

for (const path of containerSecurityOptAssets) {
  const text = readText(path);
  if (!text.includes(contract.security.requiredSecurityOpt)) {
    errors.push(`${path} must project required security opt ${contract.security.requiredSecurityOpt}`);
  }
}

if (errors.length > 0) {
  console.error("Install contract validation failed:");
  for (const error of errors) {
    console.error(`- ${error}`);
  }
  process.exit(1);
}

console.log("Install contract validation passed.");

function readJson(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

function readText(relativePath) {
  try {
    return readFileSync(resolve(root, relativePath), "utf8");
  } catch (error) {
    errors.push(`missing deploy asset ${relativePath}`);
    return "";
  }
}

function hasEnvName(text, envName) {
  return new RegExp(`(^|\\n)${escapeRegExp(envName)}=`, "m").test(text) || text.includes(envName);
}

function requireString(value, path) {
  if (typeof value !== "string" || !value) {
    errors.push(`${path} must be a non-empty string`);
  }
}

function requireArray(value, path, options = {}) {
  if (!Array.isArray(value) || (!options.allowEmpty && value.length === 0)) {
    errors.push(options.allowEmpty ? `${path} must be an array` : `${path} must be a non-empty array`);
  }
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
