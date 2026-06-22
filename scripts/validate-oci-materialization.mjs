#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(fileURLToPath(new URL("..", import.meta.url)));
const errors = [];

const linuxInstaller = readText("scripts/install/install-linux.sh");
const dockerCompose = readText("docker/docker-compose.yml");
const dockerComposeExample = readText("docker/docker-compose.example.yml");
const truenasCompose = readText("docker-compose.truenas.yml");
const truenasLocalBuild = readText("docker-compose.truenas.local-build.yml");
const truenasIxLocalImage = readText("docker-compose.truenas-ix-image-local.yml");
const linuxDocs = readText("docs/bare-metal-linux.md");
const setupDocs = readText("docs/self-hosted-setup.md");

const requiredInstallerTerms = [
  'OMNILUX_IMAGE="${OMNILUX_IMAGE:-ghcr.io/omnilux-tv/omnilux:latest}"',
  'OMNILUX_IMAGE_PLATFORM="${OMNILUX_IMAGE_PLATFORM:-}"',
  "manifest_accept_header()",
  "application/vnd.oci.image.index.v1+json",
  "application/vnd.docker.distribution.manifest.list.v2+json",
  "application/vnd.oci.image.manifest.v1+json",
  "application/vnd.docker.distribution.manifest.v2+json",
  "registry_get_manifest()",
  "select_platform_manifest_digest()",
  "list_layer_specs()",
  "mediaType.includes('nondistributable')",
  "image_revision()",
  "normalize_layer_path()",
  "apply_layer_whiteouts()",
  "remove_layer_whiteout_markers()",
  "prepare_known_symlink_conflicts()",
  "extract_layer()",
  "*zstd*",
  "*gzip*|*tar+gzip*",
  'if [[ ! -d "${rootfs_dir}/app" ]]; then',
  "Published image did not contain /app",
  "materialize_esm_symlinks",
  "write_launcher",
  '"image": "${OMNILUX_IMAGE}"',
  '"platform": "${platform}"',
  '"manifest": "${selected_digest:-${reference}}"',
  '"revision": "${revision}"',
  '"runtimeDir": "${OMNILUX_APP_DIR}"',
  "OMNILUX_REGISTRY_USERNAME",
  "OMNILUX_REGISTRY_PASSWORD",
  "OMNILUX_REGISTRY_TOKEN",
  "GHCR_TOKEN",
];

for (const term of requiredInstallerTerms) {
  requireIncludes(linuxInstaller, term, `Linux installer missing OCI materialization term: ${term}`);
}

for (const unsafePathTerm of ['/*|../*|*/../*|*/..)', 'Unsafe path in image layer']) {
  requireIncludes(linuxInstaller, unsafePathTerm, `Linux installer missing unsafe layer path guard: ${unsafePathTerm}`);
}

for (const [path, text] of [
  ["docker/docker-compose.yml", dockerCompose],
  ["docker/docker-compose.example.yml", dockerComposeExample],
  ["docker-compose.truenas.yml", truenasCompose],
]) {
  requireIncludes(
    text,
    "${OMNILUX_IMAGE:-ghcr.io/omnilux-tv/omnilux:latest}",
    `${path} must consume the official image through OMNILUX_IMAGE`,
  );
}

for (const [path, text] of [
  ["docker-compose.truenas.local-build.yml", truenasLocalBuild],
  ["docker-compose.truenas-ix-image-local.yml", truenasIxLocalImage],
]) {
  requireIncludes(text, "omnilux-truenas-local:latest", `${path} must pin the local materialized image tag`);
  requireIncludes(text, "pull_policy: never", `${path} must prevent pulling the local materialized image`);
}

for (const [path, text] of [
  ["docs/bare-metal-linux.md", linuxDocs],
  ["docs/self-hosted-setup.md", setupDocs],
]) {
  requireIncludes(text, "ghcr.io/omnilux-tv/omnilux", `${path} must document the official runtime image`);
}
requireIncludes(linuxDocs, "OCI Registry API", "Linux docs must document OCI Registry API materialization");
requireIncludes(linuxDocs, "OMNILUX_IMAGE_PLATFORM", "Linux docs must document platform selection");
requireIncludes(setupDocs, "docker login ghcr.io", "Setup docs must document registry authentication");

if (errors.length > 0) {
  console.error("OCI materialization validation failed:");
  for (const error of errors) {
    console.error(`- ${error}`);
  }
  process.exit(1);
}

console.log("OCI materialization validation passed.");

function readText(relativePath) {
  try {
    return readFileSync(resolve(root, relativePath), "utf8");
  } catch {
    errors.push(`missing deploy asset ${relativePath}`);
    return "";
  }
}

function requireIncludes(text, needle, message) {
  if (!text.includes(needle)) {
    errors.push(message);
  }
}
