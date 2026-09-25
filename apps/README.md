# apps

One directory per app. The directory name is also the Argo CD AppProject name
and the Kargo Project name.

```
apps/<name>/
├── README.md
├── argocd/     # AppProject + ApplicationSet   -> picked up by bootstrap/argocd-apps.yaml
├── kargo/      # Project, Warehouse, Stages... -> picked up by bootstrap/kargo-apps.yaml
├── base/       # Kustomize base
└── env/{staging,prod}/
```

Apps with no `kargo/` directory are deployed by Argo CD only. Apps arrive in
Phase 3.
