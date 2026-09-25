#!/usr/bin/env bash
# Prepare k3d node containers for Cilium: shared bpffs and a cgroup v2 mount.
set -euo pipefail
cluster="${1:-phase0}"
for node in $(docker ps --filter "label=k3d.cluster=${cluster}" --format '{{.Names}}'); do
  case "$node" in *serverlb) continue ;; esac
  docker exec "$node" sh -c '
    mountpoint -q /sys/fs/bpf || mount bpffs /sys/fs/bpf -t bpf
    mount --make-shared /sys/fs/bpf
    mkdir -p /run/cilium/cgroupv2
    mountpoint -q /run/cilium/cgroupv2 || mount -t cgroup2 none /run/cilium/cgroupv2
    mount --make-shared /run/cilium/cgroupv2
  '
  echo "prepared $node"
done
