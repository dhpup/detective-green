# Security

This repo is a conference demo, not a product. It deliberately contains a
network misconfiguration (the "culprit") and a privileged-by-design DaemonSet
(`node-tuner`, `hostNetwork` + `NET_ADMIN` only), both meant for local k3d
clusters. Don't point it at a cluster you care about.

## Reporting a vulnerability

If you find a real security issue (a leaked secret, a vulnerable pinned image,
something in the scripts or workflows), please report it privately using
GitHub's "Report a vulnerability" button on the Security tab, rather than
opening a public issue.

## What we do

- Every image is pinned by digest and every Helm chart by sha256 (`versions.env`).
- Our own images are built from distroless bases, run as non-root, and are
  signed with cosign keyless signing (GitHub OIDC), with SBOM and provenance
  attestations attached.
- `make verify-images` checks signatures and scans every pinned image.
- CI actions are pinned by commit SHA with least-privilege permissions.
- No secrets live in git. Local credentials are generated into `.secrets/`
  (gitignored), and gitleaks runs in pre-commit and CI.
