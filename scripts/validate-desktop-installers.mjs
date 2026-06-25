#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(fileURLToPath(new URL("..", import.meta.url)));
const errors = [];

const contract = readJson("contracts/desktop-installer-artifacts.json");
const workflow = readText(".github/workflows/desktop-installers.yml");
const readme = readText("README.md");

requireArray(contract.artifacts, "artifacts");
requireString(contract.dockerOneLine, "dockerOneLine");
requireIncludes(contract.dockerOneLine, "curl -fsSL https://omnilux.tv/self-hosted/install.sh | bash", "docker one-line command");
requireIncludes(workflow, "allow_unsigned_artifacts", "non-launch unsigned installer escape hatch");
requireIncludes(workflow, "default: false", "unsigned installer escape hatch default");
requireIncludes(workflow, "macOS installer signing secrets are required for launch-ready pkg artifacts.", "macOS launch signing hard failure");
requireIncludes(workflow, "App Store Connect notarization secrets are required for launch-ready pkg artifacts.", "macOS launch notarization hard failure");
requireIncludes(workflow, "WINDOWS_CODE_SIGNING_CERTIFICATE_BASE64 is required for launch-ready Windows installer artifacts.", "Windows launch certificate hard failure");
requireIncludes(workflow, "WINDOWS_CODE_SIGNING_CERTIFICATE_PASSWORD is required for launch-ready Windows installer artifacts.", "Windows launch signing password hard failure");

for (const artifact of contract.artifacts ?? []) {
  requireString(artifact.id, "artifact.id");
  requireString(artifact.platform, `${artifact.id}.platform`);
  requireString(artifact.fileName, `${artifact.id}.fileName`);
  requireString(artifact.checksumFileName, `${artifact.id}.checksumFileName`);
  requireString(artifact.builder, `${artifact.id}.builder`);
  requireString(artifact.runtimeInstaller, `${artifact.id}.runtimeInstaller`);

  readText(artifact.builder);
  readText(artifact.runtimeInstaller);
  requireIncludes(workflow, artifact.fileName, `workflow release asset ${artifact.fileName}`);
  requireIncludes(workflow, artifact.checksumFileName, `workflow checksum asset ${artifact.checksumFileName}`);
  requireIncludes(readme, artifact.fileName, `README release asset ${artifact.fileName}`);
}

const macosBuilder = readText("scripts/package-macos-pkg.sh");
requireIncludes(macosBuilder, "pkgbuild", "macOS pkg builder");
requireIncludes(macosBuilder, "COPYFILE_DISABLE=1", "macOS pkg excludes AppleDouble metadata");
requireIncludes(macosBuilder, "productsign", "macOS pkg signing");
requireIncludes(macosBuilder, "notarytool submit", "macOS pkg notarization");
requireIncludes(macosBuilder, 'shasum -a 256 "${PKG_PATH}"', "macOS local checksum generation");
requireIncludes(macosBuilder, "https://omnilux.tv/self-hosted/macos/install.sh", "macOS runtime installer projection");
requireIncludes(macosBuilder, "OmniLux-macOS.pkg", "macOS release artifact name");

const linuxAppRun = readText("installer/linux/AppRun");
requireIncludes(linuxAppRun, "https://omnilux.tv/self-hosted/linux/install.sh", "Linux AppImage installer endpoint");
requireIncludes(linuxAppRun, "sudo bash", "Linux native installer escalation path");
requireIncludes(workflow, "APPIMAGE_EXTRACT_AND_RUN=1", "Linux AppImage headless build mode");

const windowsInstaller = readText("installer/windows/install-omnilux.ps1");
requireIncludes(windowsInstaller, "ghcr.io/omnilux-tv/omnilux:latest", "Windows runtime image");
requireIncludes(windowsInstaller, "docker compose", "Windows Docker Compose install path");
requireIncludes(windowsInstaller, "OMNILUX_PRIMARY_DEPLOYMENT=docker-compose", "Windows deployment profile");
requireIncludes(workflow, "WINDOWS_CODE_SIGNING_CERTIFICATE_BASE64", "Windows installer signing certificate secret");
requireIncludes(workflow, "WINDOWS_CODE_SIGNING_CERTIFICATE_PASSWORD", "Windows installer signing password secret");
requireIncludes(workflow, "signtool.exe", "Windows Authenticode signing tool");
requireIncludes(workflow, "timestamp.digicert.com", "Windows timestamp authority");
requireIncludes(workflow, "Get-FileHash dist\\installers\\OmniLux-Setup.exe -Algorithm SHA256", "Windows checksum generation");

const nsi = readText("installer/windows/OmniLux.nsi");
requireIncludes(nsi, "OmniLux-Setup.exe", "Windows release artifact name");
requireIncludes(nsi, "install-omnilux.ps1", "Windows PowerShell installer payload");

const publishScript = readText("scripts/publish-desktop-installers.sh");
const verifyScript = readText("scripts/verify-public-desktop-installers.sh");
requireIncludes(publishScript, "gh workflow run", "desktop installer publish workflow trigger");
requireIncludes(publishScript, "gh run watch", "desktop installer publish workflow wait");
requireIncludes(publishScript, "verify-public-desktop-installers.sh", "desktop installer public verification step");
requireIncludes(verifyScript, "OmniLux-macOS.pkg", "public macOS installer verification");
requireIncludes(verifyScript, "OmniLux-Linux.AppImage", "public Linux installer verification");
requireIncludes(verifyScript, "OmniLux-Setup.exe", "public Windows installer verification");

for (const secret of [
  "MACOS_INSTALLER_CERTIFICATE_BASE64",
  "MACOS_INSTALLER_CERTIFICATE_PASSWORD",
  "MACOS_INSTALLER_KEYCHAIN_PASSWORD",
  "APP_STORE_CONNECT_API_KEY_ID",
  "APP_STORE_CONNECT_API_ISSUER_ID",
  "APP_STORE_CONNECT_API_KEY_P8",
]) {
  requireIncludes(workflow, secret, `desktop installer workflow secret ${secret}`);
}

if (errors.length > 0) {
  console.error("Desktop installer validation failed:");
  for (const error of errors) {
    console.error(`- ${error}`);
  }
  process.exit(1);
}

console.log("Desktop installer validation passed.");

function readJson(relativePath) {
  return JSON.parse(readText(relativePath));
}

function readText(relativePath) {
  try {
    return readFileSync(resolve(root, relativePath), "utf8");
  } catch {
    errors.push(`missing desktop installer asset ${relativePath}`);
    return "";
  }
}

function requireString(value, path) {
  if (typeof value !== "string" || !value) {
    errors.push(`${path} must be a non-empty string`);
  }
}

function requireArray(value, path) {
  if (!Array.isArray(value) || value.length === 0) {
    errors.push(`${path} must be a non-empty array`);
  }
}

function requireIncludes(text, term, label) {
  if (!text.includes(term)) {
    errors.push(`${label} must include ${term}`);
  }
}
