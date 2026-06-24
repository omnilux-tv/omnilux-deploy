# OmniLux Self-Hosted Deploy Contract

This context defines the language for the official reusable install and deployment contract for customer-owned OmniLux servers.

`omnilux-deploy/` succeeds when a customer or operator can install, upgrade, validate, and operate an official self-hosted OmniLux runtime from published artifacts across supported paths (Docker, TrueNAS, bare-metal Linux, bare-metal macOS) without cloning product source or encoding host-specific or private infrastructure into the org repo.

In short, `omnilux-deploy/` is the official self-hosted installation and operations contract. It turns published OmniLux runtime artifacts into supported customer install paths with reusable environment, volume, service, validation, update, rollback, and CLI behavior, while excluding product runtime code, artifact publishing, public edge, managed product deploys, and private host-specific infrastructure.

## Language

**Self-Hosted Deploy Contract**:
The supported installation, upgrade, environment, volume, and health-check contract for customer-owned OmniLux runtimes.
_Avoid_: Product runtime, private deployment, edge deploy

**Supported Install Path**:
A documented, validated, artifact-based way to install the self-hosted runtime.
_Avoid_: Retired setup script, personal script, one-off host setup

**Artifact-Based Install**:
A deploy flow that consumes OCI images or release tarballs published by product repos without building from sibling source checkouts or requiring product source on the target host.
_Avoid_: Source install, local build deploy

**Runtime Management CLI**:
The post-install command interface used to inspect and manage an installed self-hosted runtime.
_Avoid_: Developer script, app CLI

**Runtime Operations Contract**:
The post-install contract for CLI behavior, service start, stop, status, logs, update, backup hooks where supported, environment and volume expectations, health checks, and safe update or rollback conventions.
_Avoid_: Product runtime behavior, application feature

**Deployment Profile**:
The declared install shape and runtime mode used by deployment assets.
_Avoid_: Environment, branch, host type

**TrueNAS Catalog Target**:
The future distribution goal of making the self-hosted runtime installable through the TrueNAS catalog.
_Avoid_: Current supported install path, host-specific TrueNAS override

**Published Runtime Image**:
The official OCI image consumed by deploy assets instead of rebuilding from product source.
_Avoid_: Source checkout, local build

**Host-Specific Override**:
Machine-specific paths, secrets, credentials, or wrapper scripts that must live outside the official deploy contract.
_Avoid_: Deploy contract, reusable install asset

**Self-Hosted Deploy Boundary**:
The rule that this repo owns official self-hosted runtime deploy only, not managed-media, operator-console, provider-portal, public-edge, or private deploy contracts.
_Avoid_: First-party managed deploy, ops deploy, provider deploy

**Deploy Exclusion Boundary**:
The application, artifact-publishing, cloud, edge, private-host, managed product, plugin, and native packaging responsibilities intentionally owned outside the self-hosted deploy repo.
_Avoid_: Runtime source ownership, personal infrastructure, all deploy work

## Relationships

- A **Self-Hosted Deploy Contract** defines one or more **Supported Install Paths**.
- A **Supported Install Path** uses an **Artifact-Based Install**.
- A **Supported Install Path** can install a **Published Runtime Image** or equivalent published artifact.
- Current **Supported Install Paths** are Docker/image, TrueNAS Compose, bare-metal Linux `systemd`, and bare-metal macOS `launchd`.
- Retired Windows and legacy setup scripts are not **Supported Install Paths**.
- The **TrueNAS Catalog Target** is a deferred distribution goal; today's TrueNAS support is the artifact-based Compose/custom-app path.
- The **TrueNAS Catalog Target** becomes a **Supported Install Path** only after reusable catalog packaging, install and upgrade validation, update and rollback behavior, environment and volume mapping, and docs are in place.
- A **Runtime Management CLI** operates after a **Supported Install Path** completes.
- The **Runtime Operations Contract** defines how an installed runtime is managed without owning product behavior after the runtime process starts.
- A **Host-Specific Override** consumes the **Self-Hosted Deploy Contract** but does not belong in this repo.
- This repo owns the install contract for artifact consumption, not artifact publishing.
- The **Self-Hosted Deploy Boundary** keeps managed-media deploy in `omnilux-media/`, operator-console deploy in `omnilux-ops/`, and provider-portal deploy in `omnilux-provider/` or edge/platform contracts as they mature.
- The **Deploy Exclusion Boundary** keeps runtime behavior, runtime image publishing, cloud schema and functions, public edge routing, personal host state, managed product deploys, plugin implementation, and native packaging outside this repo.

## Example dialogue

> **Dev:** "Should we add my TrueNAS hostname and private mount paths here?"
> **Domain expert:** "No. Those are **Host-Specific Overrides**. This repo owns the reusable **Self-Hosted Deploy Contract**."

## Flagged ambiguities

- "Deploy" can mean customer self-hosted deploy or OmniLux public edge deploy. Resolved: this repo uses **Self-Hosted Deploy Contract** for customer-owned runtime installs.
- First-party managed, ops, or provider deploy work could drift into this repo. Resolved: the **Self-Hosted Deploy Boundary** keeps this repo focused on official self-hosted runtime deploy.
- Deploy assets can become a dumping ground for runtime, cloud, edge, or private host concerns. Resolved: the **Deploy Exclusion Boundary** defines what this repo must not own.
- "Install" could imply source builds on target hosts. Resolved: supported flows are **Artifact-Based Installs**.
- TrueNAS support can mean today's Compose/custom-app path or a future catalog listing. Resolved: **TrueNAS Catalog Target** names the future goal without treating it as current support.
