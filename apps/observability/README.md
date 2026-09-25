# observability

kube-prometheus-stack in both workload clusters (Argo CD only, no Kargo):
Prometheus, Grafana, node-exporter and kube-state-metrics, trimmed for a
laptop. See `values.yaml` for what's on and off, and why.

| | staging | prod |
|---|---|---|
| Grafana | http://localhost:3001 | http://localhost:3002 |
| Prometheus (from the k3d network) | `k3d-staging-server-0:30090` | `k3d-prod-server-0:30090` |

Kargo's AnalysisRuns (Phase 4) query staging's Prometheus on its NodePort.

- `values.yaml`: chart values; every image pinned by digest.
- `env/<cluster>/values.yaml`: per-cluster overrides.
- `manifests/`: extra resources, e.g. the ServiceMonitor for Hubble metrics.
