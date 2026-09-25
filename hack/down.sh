#!/usr/bin/env bash
# Deletes all three clusters. Other k3d clusters on this machine are untouched.
source "$(dirname "$0")/lib/common.sh"
for cluster in "${ALL_CLUSTERS[@]}"; do
  k3d cluster delete "$cluster" 2>/dev/null || true
done
docker network rm "$NETWORK" >/dev/null 2>&1 || true
log "lab deleted"
