#!/usr/bin/env bash
# Creates the whole lab: staging + prod (Cilium) and mgmt (Argo CD, Rollouts, Kargo).
# Idempotent: existing clusters are reused and charts are upgraded in place.
source "$(dirname "$0")/lib/common.sh"

"${ROOT}/hack/doctor.sh" >/dev/null

log "building evidence-kit (used to set NIC offloads)"
docker build -q --build-arg BASE_IMAGE="$ALPINE_IMAGE" -t detective/evidence-kit:local "${ROOT}/src/evidence-kit" >/dev/null

for cluster in "${ALL_CLUSTERS[@]}"; do
  if k3d cluster get "$cluster" >/dev/null 2>&1; then
    log "cluster ${cluster} exists"
  else
    log "creating cluster ${cluster}"
    k3d cluster create --config "${ROOT}/hack/k3d/${cluster}.yaml" --image "$K3S_IMAGE" --wait=false >/dev/null
  fi
done

for cluster in "${WORKLOAD_CLUSTERS[@]}"; do
  "${ROOT}/hack/prepare-nodes.sh" "$cluster"
  "${ROOT}/hack/install-cilium.sh" "$cluster"
done

"${ROOT}/hack/install-control-plane.sh"
"${ROOT}/hack/register-clusters.sh"
"${ROOT}/hack/status.sh"

cat <<MSG

Argo CD  https://localhost:8443  admin / $(kubectl --context "$(ctx mgmt)" -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
Kargo    https://localhost:8444  admin / $(cat "${SECRETS_DIR}/kargo-admin-password")
(Both use self-signed certificates.)

Next: push this repo to GitHub, then run 'make bootstrap'.
MSG
