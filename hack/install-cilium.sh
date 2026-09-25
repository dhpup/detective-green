#!/usr/bin/env bash
# Installs Cilium (+ Hubble) into a workload cluster. The CNI is installed by
# script, not Argo CD, because nothing else can run until it exists.
#
# Usage: hack/install-cilium.sh <cluster>
source "$(dirname "$0")/lib/common.sh"

cluster="${1:?usage: $0 <cluster>}"

log "installing Cilium ${CILIUM_CHART_VERSION} into ${cluster}"
helm_install cilium cilium kube-system "$(ctx "$cluster")" \
  --set k8sServiceHost="k3d-${cluster}-server-0"
kubectl --context "$(ctx "$cluster")" -n kube-system rollout status ds/cilium --timeout=180s >/dev/null
kubectl --context "$(ctx "$cluster")" wait --for=condition=Ready nodes --all --timeout=180s >/dev/null
log "Cilium ready in ${cluster}"
