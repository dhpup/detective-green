#!/usr/bin/env bash
# Make the k3d network behave like a real wire: turn off segmentation offload on every
# node's eth0, and GRO/segmentation offload on the VM-side veths of the cluster's bridge.
# With offload on, veth pairs pass oversized GSO/GRO packets without checking the MTU,
# which hides the black hole. Needs re-running if a node container restarts.
set -euo pipefail
cluster="${1:-phase0}"
img="${EVIDENCE_KIT:-detective/evidence-kit:phase0}"
for node in $(docker ps --filter "label=k3d.cluster=${cluster}" --format '{{.Names}}'); do
  case "$node" in *serverlb) continue ;; esac
  docker run --rm --net "container:${node}" --cap-add NET_ADMIN --entrypoint ethtool "$img" \
    -K eth0 tso off gso off tx-udp_tnl-segmentation off tx-udp_tnl-csum-segmentation off >/dev/null 2>&1 || true
  echo "offloads off: $node"
done

# VM side: only the veths attached to this cluster's bridge (other clusters are untouched).
network="$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' "k3d-${cluster}-server-0")"
bridge="br-$(docker network inspect "$network" -f '{{.Id}}' | cut -c1-12)"
docker run --rm --net host --cap-add NET_ADMIN --entrypoint sh "$img" -c "
  for v in \$(ls /sys/class/net | grep veth); do
    [ \"\$(basename \$(readlink /sys/class/net/\$v/master 2>/dev/null) 2>/dev/null)\" = $bridge ] || continue
    ethtool -K \$v gro off tso off gso off >/dev/null 2>&1 || true
    echo \"offloads off: VM \$v ($bridge)\"
  done"
