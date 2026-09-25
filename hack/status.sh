#!/usr/bin/env bash
# One-screen summary of the lab.
source "$(dirname "$0")/lib/common.sh"

for cluster in "${ALL_CLUSTERS[@]}"; do
  if ! k3d cluster get "$cluster" >/dev/null 2>&1; then
    printf '%-8s not created\n' "$cluster"; continue
  fi
  ready="$(kubectl --context "$(ctx "$cluster")" get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l | tr -d ' ')"
  total="$(kubectl --context "$(ctx "$cluster")" get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  printf '%-8s nodes %s/%s ready\n' "$cluster" "$ready" "$total"
done
if k3d cluster get mgmt >/dev/null 2>&1; then
  echo; echo "Argo CD clusters:"
  kubectl --context "$(ctx mgmt)" -n argocd get secret -l argocd.argoproj.io/secret-type=cluster \
    -o jsonpath='{range .items[*]}{"  "}{.metadata.name}{"\n"}{end}' 2>/dev/null
  echo "Argo CD applications:"
  kubectl --context "$(ctx mgmt)" -n argocd get applications 2>/dev/null | sed 's/^/  /' || true
fi
