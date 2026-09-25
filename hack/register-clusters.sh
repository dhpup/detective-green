#!/usr/bin/env bash
# Registers clusters with Argo CD on mgmt, using the same names akp-platform expects:
#   staging, prod  -> the workload clusters, reached over the shared k3d network
#   kargo          -> the mgmt cluster itself, where Kargo runs (bootstrap/kargo-apps.yaml
#                     syncs Kargo resources to the destination named `kargo`)
# Each gets a ServiceAccount token created at runtime. Tokens go straight into
# Argo CD cluster secrets and are never written to disk.
source "$(dirname "$0")/lib/common.sh"

mgmt="$(ctx mgmt)"

# register <argocd-name> <kube-context> <server-url>
register() {
  local name="$1" context="$2" server="$3" token ca
  kubectl --context "$context" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: ServiceAccount
metadata: {name: argocd-manager, namespace: kube-system}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: {name: argocd-manager}
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: cluster-admin}
subjects: [{kind: ServiceAccount, name: argocd-manager, namespace: kube-system}]
---
apiVersion: v1
kind: Secret
metadata:
  name: argocd-manager-token
  namespace: kube-system
  annotations: {kubernetes.io/service-account.name: argocd-manager}
type: kubernetes.io/service-account-token
YAML
  for _ in $(seq 1 30); do
    token="$(kubectl --context "$context" -n kube-system get secret argocd-manager-token -o jsonpath='{.data.token}' 2>/dev/null | base64 -d)"
    [[ -n "$token" ]] && break
    sleep 1
  done
  [[ -n "$token" ]] || die "no ServiceAccount token issued in ${context}"
  ca="$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name=='${context}')].cluster.certificate-authority-data}")"

  kubectl --context "$mgmt" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: cluster-${name}
  namespace: argocd
  labels: {argocd.argoproj.io/secret-type: cluster}
type: Opaque
stringData:
  name: ${name}
  server: ${server}
  config: '{"bearerToken":"${token}","tlsClientConfig":{"caData":"${ca}"}}'
YAML
  log "registered ${name} -> ${server}"
}

for env in "${WORKLOAD_CLUSTERS[@]}"; do
  register "$env" "$(ctx "$env")" "https://k3d-${env}-server-0:6443"
done
# A second URL for the in-cluster API, so it can carry the name `kargo`
# alongside Argo CD's built-in `in-cluster` entry.
register kargo "$mgmt" "https://kubernetes.default.svc.cluster.local:443"
