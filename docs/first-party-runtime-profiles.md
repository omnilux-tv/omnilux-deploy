# First-Party Runtime Profiles

The `omnilux` runtime image is shared across three deployment profiles:

- `self-hosted` — normal customer-owned runtime
- `managed-media` — first-party OmniLux runtime behind `media.omnilux.tv`
- `ops` — internal OmniLux runtime behind `ops.omnilux.tv`

This repo is the official deploy contract for all three profiles.

## Required environment contract

Every first-party runtime should set:

- `OMNILUX_DEPLOYMENT_PROFILE`
- `OMNILUX_PUBLIC_ORIGIN`
- `OMNILUX_CLOUD_APP_URL=https://app.omnilux.tv`
- `SUPABASE_URL=https://api.omnilux.tv`
- `SUPABASE_ANON_KEY`
- `OMNILUX_ALLOWED_ORIGINS`

Profile-specific examples live in:

- `deploy/first-party/managed-media.env.example`
- `deploy/first-party/ops.env.example`

## Control-plane behavior

First-party runtimes do not use customer claim codes.

They self-register through OmniLux Cloud using the runtime profile contract already built into `omnilux`:

- `managed-media` should appear to entitled cloud users
- `ops` should appear only to operator accounts

## Deployment shape

Use one of these supported patterns:

1. Run the profile directly on the public edge host via `omnilux-edge` compose profiles `media` and `ops`.
2. Run the profile on a dedicated Docker host using `deploy/first-party/docker-compose.runtime.yml` and route traffic through `omnilux-edge`.

Private host-specific copies of these env files belong in the private `omnilux-infra` repo, not here.
