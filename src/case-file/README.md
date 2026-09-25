# case-file

The demo app. One Go binary, one signed distroless image, five roles:

| Mode | Role in the story | What it does |
|---|---|---|
| `evidence-locker` | the API | `GET /api/evidence?size=N` returns N bytes, `POST /api/evidence` accepts an upload. Every response carries `X-Node` |
| `frontdesk` | the frontend | Forwards `/api/evidence` to an evidence-locker pod picked from the headless Service's DNS records |
| `informant` | the city's users | Sends a steady mix of small and large downloads and uploads through frontdesk |
| `sweep` | the promotion gate | Sends every size, both ways, several times; exits non-zero if anything fails |
| `tuner` | node-tuner (the culprit's vehicle) | Sets a node's `eth0` MTU and keeps it there |

Every server mode also serves `GET /healthz` (tiny on purpose: it's what the
probes check, and why they stay green) and `GET /metrics`.

## Why frontdesk talks to pods directly

The MTU black hole breaks the frontdesk → evidence-locker hop, so that's where
the evidence is. frontdesk resolves the headless Service itself and connects to
a pod IP, one fresh connection per request. That lets it:

- say which node each request went to (`dst_node`), even when the request
  fails, because it remembers pod IP → node from earlier successful responses;
- read the kernel's `TCP_INFO` for exactly that connection, and count the
  segments TCP had to retransmit.

A failed upload comes back as a 504 carrying that evidence:

```
504 upstream evidence-locker 10.42.1.93 on node k3d-staging-agent-1 failed after 4.007s:
Post "http://10.42.1.93:8080/api/evidence": context deadline exceeded (5 TCP retransmits)
```

The sweep prints that message as-is, so the gate's log shows the same
retransmits you'd find in a pcap.

## Metrics

| Metric | From |
|---|---|
| `case_file_upstream_requests_total{method,size_bucket,dst_node,result}` | frontdesk |
| `case_file_upstream_tcp_retransmits_total{dst_node}` | frontdesk (from `TCP_INFO`) |
| `case_file_upstream_duration_seconds{method,size_bucket,result}` | frontdesk |
| `case_file_probe_requests_total{method,size_bucket,dst_node,result}` | informant |
| `case_file_probe_duration_seconds{method,size_bucket,result}` | informant |
| `case_file_api_requests_total{method,size_bucket,code}` | evidence-locker |
| `case_file_tuner_interface_mtu{interface}` | tuner |

`size_bucket` is `small` (≤ 1 KiB), `medium` (≤ 64 KiB) or `large`.

## Build and test

```bash
make test     # vet, race tests, govulncheck, golangci-lint (pinned containers)
make images   # build detective/case-file:local and scan it with Trivy
```

Releases are built by `.github/workflows/release.yaml` on a `v*.*.*` tag:
scanned, built for amd64 and arm64 with SBOM and provenance attestations,
pushed to `ghcr.io/<owner>/case-file`, and signed with keyless cosign.

`tuner` needs root with only `CAP_NET_ADMIN` and `hostNetwork` (it changes the
node's interface). Every other mode runs as UID 65532 with no capabilities.
