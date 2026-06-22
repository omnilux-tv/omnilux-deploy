#!/usr/bin/env node
import { existsSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(fileURLToPath(new URL("..", import.meta.url)));
const workspaceRoot = resolve(root, "..");
const publicDocsRoot = join(workspaceRoot, "docs");

if (!existsSync(publicDocsRoot)) {
  console.log("Public docs repo not present; skipping docs projection validation.");
  process.exit(0);
}

const contract = JSON.parse(readFileSync(join(root, "contracts/install-contract.json"), "utf8"));
const publicDocs = readMany([
  "guide/installation/docker.md",
  "guide/installation/bare-metal.md",
  "guide/installation/bare-metal-macos.md",
  "guide/installation/environment-variables.md",
  "guide/installation/truenas.md",
  "guide/installation/updating.md",
], publicDocsRoot);
const deployDocs = readMany([
  "README.md",
  "docs/self-hosted-setup.md",
  "docs/bare-metal-linux.md",
  "docs/bare-metal-macos.md",
  "docs/runtime-cli.md",
], root);

const requiredTerms = [
  contract.image.default,
  contract.image.envVar,
  contract.healthcheck.path,
  contract.volumes.find((volume) => volume.name === "omnilux-plugins")?.target,
  contract.platforms.find((platform) => platform.id === "linux")?.entrypoint,
  contract.platforms.find((platform) => platform.id === "macos")?.entrypoint,
].filter(Boolean);

const errors = [];
for (const term of requiredTerms) {
  if (!publicDocs.includes(term)) {
    errors.push(`public docs do not project install contract term: ${term}`);
  }
  if (!deployDocs.includes(term)) {
    errors.push(`deploy docs do not project install contract term: ${term}`);
  }
}

if (errors.length > 0) {
  console.error("Docs projection validation failed:");
  for (const error of errors) {
    console.error(`- ${error}`);
  }
  process.exit(1);
}

console.log("Docs projection validation passed.");

function readMany(paths, baseDir) {
  return paths
    .map((path) => {
      const fullPath = join(baseDir, path);
      return existsSync(fullPath) ? readFileSync(fullPath, "utf8") : "";
    })
    .join("\n");
}
