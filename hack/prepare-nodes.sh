#!/usr/bin/env bash
# Prepares a workload cluster's k3d node containers before Cilium is installed:
#   1. Mounts bpffs and a cgroup v2 path inside each node (Cilium needs both,
#      and k3d nodes don't have them).
#   2. Turns off NIC offloads so the Docker network behaves like a real wire:
#      segmentation offload on each node's eth0, and GRO/segmentation offload on
#      the VM-side veths of the shared bridge. With offloads on, veth pairs pass
#      oversized packets without checking the MTU and the black hole never shows
#      (docs/reproducing-the-black-hole.md, finding 1).
# Safe to re-run. Needs re-running if a node container restarts.
#
# Usage: hack/prepare-nodes.sh <cluster>
source "$(dirname "$0")/lib/common.sh"

cluster="${1:?usage: $0 <cluster>}"
kit="detective/evidence-kit:local"

nodes() {
  docker ps --filter "label=k3d.cluster=${cluster}" --format '{{.Names}}' | grep -v serverlb
}

for node in $(nodes); do
  docker exec "$node" sh -c '
    mountpoint -q /sys/fs/bpf || mount bpffs /sys/fs/bpf -t bpf
    mount --make-shared /sys/fs/bpf
    mkdir -p /run/cilium/cgroupv2
    mountpoint -q /run/cilium/cgroupv2 || mount -t cgroup2 none /run/cilium/cgroupv2
    mount --make-shared /run/cilium/cgroupv2'
  docker run --rm --net "container:${node}" --cap-add NET_ADMIN --entrypoint ethtool "$kit" \
    -K eth0 tso off gso off tx-udp_tnl-segmentation off tx-udp_tnl-csum-segmentation off >/dev/null 2>&1 || true
  log "prepared ${node} (bpffs, cgroup2, eth0 offloads off)"
done

# VM side: only veths attached to this cluster's bridge are touched.
bridge="br-$(docker network inspect "$NETWORK" -f '{{.Id}}' | cut -c1-12)"
docker run --rm --net host --cap-add NET_ADMIN --entrypoint sh "$kit" -c "
  for v in \$(ls /sys/class/net | grep veth); do
    [ \"\$(basename \$(readlink /sys/class/net/\$v/master 2>/dev/null) 2>/dev/null)\" = ${bridge} ] || continue
    ethtool -K \$v gro off tso off gso off >/dev/null 2>&1 || true
  done"
log "VM-side veth offloads off on ${bridge}"
