# The Case of the Green Dashboard

Argo CD says **Synced**. Every pod is **Healthy**. And users are timing out.

This is the demo repo for the KubeCon talk *The Case of the Green Dashboard: A
GitOps Whodunit at the Packet Level*. It builds a small laptop lab where a
routine platform change breaks large requests while every health check stays
green, then shows how to find the culprit with packet captures and stop it next
time with a promotion gate.

Everything here is open source: k3d, Cilium + Hubble, Argo CD, Argo Rollouts,
Kargo, tcpdump and Wireshark.

> **Status:** the lab, the apps, the promotion gate and the scene scripts
> work. Rehearsal material (runbook, recordings) is still to come.

## Reproduce the case at home

Prerequisites: [OrbStack](https://orbstack.dev) (or another Docker runtime),
[k3d](https://k3d.io), `kubectl`, `helm`, `python3`, `openssl`, `htpasswd`.
Tested on OrbStack. About 12 GB of RAM free is comfortable.

```bash
make doctor      # check prerequisites
make up          # staging + prod (Cilium) and mgmt (Argo CD, Argo Rollouts, Kargo)
make bootstrap   # point Argo CD at this repo
GITHUB_USER=<you> make credentials   # a token Kargo can push rendered/* branches with
make reset       # the "2am" state: all green, users failing
make scene-4     # ...and so on through the chapters: see docs/scenes.md
make down        # delete it all; other k3d clusters are untouched
```

`make up` prints the Argo CD and Kargo URLs and admin passwords. Both UIs use
self-signed certificates and listen on localhost only:

| UI | URL |
|---|---|
| Argo CD | https://localhost:8443 |
| Kargo | https://localhost:8444 |
| Grafana, staging / prod ("Precinct Board") | http://localhost:3001 / http://localhost:3002 |

### Using your own fork

```bash
hack/personalize.sh <your-github-user>   # rewrites repo URLs and image owners
git commit -am "personalize" && git push
make up bootstrap
GITHUB_USER=<you> make credentials   # prompts for a fine-grained token
```

Use a fine-grained GitHub token scoped to your fork only, with *Contents: read
and write*. Kargo uses it to push the `rendered/*` branches.

## How it's laid out

```
bootstrap/      root app-of-apps; the only thing applied by hand (make bootstrap)
apps/           one directory per app: argocd/, kargo/, base/, env/<stage>/
kargo-shared/   ClusterAnalysisTemplates: the reusable checks that gate promotions
hack/           cluster setup scripts, pinned values, lint and verification
src/            the images we build
evidence/       reference packet captures
docs/           write-ups, starting with reproducing-the-black-hole.md
versions.env    every pinned version, chart sha256 and image digest
```

The GitOps layout follows [akuity/akp-platform](https://github.com/akuity/akp-platform):
the app directory name is also the Argo CD AppProject and Kargo Project name,
and ApplicationSets discover `apps/*/argocd` and `apps/*/kargo`, so adding an
app never touches `bootstrap/`.

## The lab

| Cluster | What runs there |
|---|---|
| `staging`, `prod` | 1 server + 2 agents each. The agents are two node pools, `pool=green` and `pool=blue`. Cilium in VXLAN mode with Hubble |
| `mgmt` | cert-manager, Argo Rollouts, Argo CD and Kargo |

All three share one Docker network, so Argo CD and Kargo on `mgmt` reach the
workload clusters by node name. Setting up the black hole on k3d needed a few
non-default settings (NIC offloads off, Cilium's MTU pinned, TCP MTU probing
off); [docs/reproducing-the-black-hole.md](docs/reproducing-the-black-hole.md)
explains each one.

## Supply chain

- Every Helm chart is pinned by version **and** sha256, and every image by
  digest (`versions.env`). `make verify-pins` checks both; CI runs it on every PR.
- `make verify-images` verifies cosign signatures where publishers sign, and
  scans every pinned image with Trivy.
- `make lint` runs the same pre-commit hooks as CI (yamllint, shellcheck,
  actionlint, gitleaks and more) in a container.

See [SECURITY.md](SECURITY.md) for how to report a vulnerability.

## License

[Apache-2.0](LICENSE)
