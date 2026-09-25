#!/usr/bin/env bash
# Delete the Phase 0 cluster and its network.
set -euo pipefail
k3d cluster delete phase0
