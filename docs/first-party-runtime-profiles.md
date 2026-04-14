# First-Party Runtime Profiles Moved

`omnilux-deploy` is the official deploy contract for the self-hosted `omnilux` runtime only.

First-party OmniLux-owned runtime deploy contracts now live in the dedicated product repos:

- `../omnilux-media/` owns the managed runtime image and deploy contract for `media.omnilux.tv`
- `../omnilux-ops/` owns the operator-console image and deploy contract for `ops.omnilux.tv`

Use those repos for:

- first-party image publishing
- managed runtime environment examples
- first-party runtime Docker contracts
- operator-console deployment ownership

Private host-specific copies of those env files still belong in the private `omnilux-infra` repo, not here.

The old first-party profile files were intentionally removed from `omnilux-deploy` so this repo cannot drift into split ownership for `media.omnilux.tv` or `ops.omnilux.tv`.
