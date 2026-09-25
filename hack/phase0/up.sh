#!/usr/bin/env bash
# Phase 0 one-command repro: k3d cluster + Cilium + payload servers, then break and sweep.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=../../versions.env
source ../../versions.env
CILIUM_VERSION="${CILIUM_CHART_VERSION}"

docker build -q -t detective/evidence-kit:phase0 ../../src/evidence-kit >/dev/null
docker build -q -t detective/payload:phase0 payload >/dev/null

k3d cluster list phase0 >/dev/null 2>&1 || k3d cluster create --config k3d-phase0.yaml --image "$K3S_IMAGE" --wait=false
./mount-bpf.sh phase0
./offloads-off.sh phase0

helm repo add cilium https://helm.cilium.io >/dev/null 2>&1 || true
helm upgrade --install cilium cilium/cilium --version "$CILIUM_VERSION" -n kube-system \
  --kube-context k3d-phase0 -f cilium-values.yaml --wait --timeout 5m >/dev/null
kubectl --context k3d-phase0 -n kube-system rollout status ds/cilium --timeout=180s

k3d image import detective/payload:phase0 -c phase0 >/dev/null
kubectl --context k3d-phase0 apply -f workload.yaml
kubectl --context k3d-phase0 -n phase0 wait --for=condition=Ready pod --all --timeout=120s

echo "--- healthy baseline"; ./sweep.sh blue | tail -1
echo "--- culprit: blue eth0 MTU 1450"; ./culprit.sh break >/dev/null
./sweep.sh blue || true
echo "Run './culprit.sh fix' to restore, './reliability.sh 20' for the reliability test."
