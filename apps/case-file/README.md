# case-file

**The victim.** A frontend (`frontdesk`) and an API (`evidence-locker`),
promoted by Kargo from `staging` to `prod` with the rendered-manifests pattern
(copied from akp-platform's `guestbook-rendered`, trimmed to two stages).

- `evidence-locker`: 2 replicas, one per node pool (green and blue), behind a
  headless Service.
- `frontdesk`: 1 replica on green, behind NodePort 30080 (the gate's sweep
  comes in here). It connects to API pod IPs directly; see
  `src/case-file/README.md` for why.
- Probes hit `/healthz`, which is tiny. That's why everything stays green.

## Promotion

- The Warehouse makes new Freight from new `ghcr.io/dhpup/case-file` semver
  tags and from commits to `apps/case-file/` on main.
- `staging` auto-promotes. `prod` is manual.
- Each promotion renders `env/<stage>` to plain YAML, pins the image **by
  digest**, and force-pushes it to `rendered/case-file/<stage>`. Argo CD tracks
  that branch, so what's running is always readable as plain manifests.

Until a stage's first promotion its branch doesn't exist, and its Argo CD
Application shows a comparison error. That's expected.
