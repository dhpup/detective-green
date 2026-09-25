#!/usr/bin/env bash
# Simulate the culprit on the blue node: "break" lowers eth0 MTU to 1450, "fix" restores 1500.
set -euo pipefail
node="${NODE:-k3d-phase0-agent-1}"
case "${1:-}" in
  break) docker exec "$node" ip link set dev eth0 mtu 1450 ;;
  fix)   docker exec "$node" ip link set dev eth0 mtu 1500 ;;
  *) echo "usage: $0 break|fix" >&2; exit 2 ;;
esac
docker exec "$node" cat /sys/class/net/eth0/mtu
