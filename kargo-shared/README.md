# kargo-shared

Cluster-scoped Argo Rollouts `ClusterAnalysisTemplate`s: the reusable checks
that gate promotions. Any Stage in any Kargo Project can use them:

```yaml
verification:
  analysisTemplates:
  - kind: ClusterAnalysisTemplate
    name: payload-sweep
```

Synced by `bootstrap/kargo-shared.yaml`. The checks themselves arrive in Phase 4
(`payload-sweep.yaml`, `network-signals.yaml`).
