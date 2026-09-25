#!/usr/bin/env bash
# Checks local prerequisites for `make up`.
source "$(dirname "$0")/lib/common.sh"

missing=0
for tool in docker k3d kubectl helm python3 openssl htpasswd; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf '  %-10s ok\n' "$tool"
  else
    printf '  %-10s MISSING\n' "$tool"; missing=1
  fi
done
docker info >/dev/null 2>&1 || { echo "  docker daemon not reachable (is OrbStack running?)"; missing=1; }
have="$(k3d version 2>/dev/null | awk '/k3d version/{print $3}')"
[[ "$have" == "$K3D_VERSION" ]] || echo "  note: k3d ${have:-?} installed, tested with ${K3D_VERSION}"
command -v kargo >/dev/null 2>&1 || echo "  note: the kargo CLI is needed for the scenes (make reset, make scene-*)"
[[ "$missing" == 0 ]] || die "install the missing prerequisites above"
