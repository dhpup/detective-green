# kargo-shared

Cluster-scoped Argo Rollouts `ClusterAnalysisTemplate`s: the reusable checks
that gate promotions. Any Stage in any Kargo Project can use them:

```yaml
verification:
  analysisTemplates:
  - kind: ClusterAnalysisTemplate
    name: payload-sweep
```

Synced by `bootstrap/kargo-shared.yaml`.

| Template | Provider | Passes when |
|---|---|---|
| `payload-sweep` | Job (in the Kargo cluster) | every size 1K..4M, download and upload, 4x each, succeeds through staging's frontdesk |
| `network-signals` | Prometheus (staging) | eth0 drops+errors = 0, informant large-payload success >= 99%, Hubble POLICY_DENIED drops = 0 |

Both are standard Argo Rollouts resources. The same files work for Argo
Rollouts canary analysis; Kargo runs them as a gate between environments.
`case-file`'s staging Stage uses them from day one. `node-network`'s staging
Stage gets them in Chapter 6 (branch `scene-6/gate-the-platform`).
