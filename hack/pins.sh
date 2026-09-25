#!/usr/bin/env bash
# Helper for bumping versions.env by hand. For every image pinned as
# repo:tag@digest, prints the digest the tag points to *now*, so drift and
# re-tagged images stand out. To bump a chart, change its version, run
# `hack/pins.sh chart <name> <repo|oci-ref> <version>` for the new sha256.
source "$(dirname "$0")/lib/common.sh"

if [[ "${1:-}" == chart ]]; then
  name="$2" repo="$3" version="$4" tmp="$(mktemp -d)"
  if [[ "$repo" == https://* ]]; then
    helm pull "$name" --repo "$repo" --version "$version" --destination "$tmp" >/dev/null
    sha256_of "$tmp/${name}-${version}.tgz"
  else
    die "OCI charts: bump KARGO_CHART_VERSION, set KARGO_CHART_SHA256 to anything, and fetch_chart's error prints the real digest"
  fi
  rm -rf "$tmp"; exit 0
fi

printf '%-26s %-8s %s\n' VARIABLE STATUS "IMAGE"
grep -E '^[A-Z0-9_]+=[^ ]+:[^@ ]+@sha256:' "${ROOT}/versions.env" | while IFS='=' read -r var ref; do
  current="$(python3 "${ROOT}/hack/lib/oci.py" digest "${ref%@*}" 2>/dev/null || echo "?")"
  if [[ "$current" == "${ref#*@}" ]]; then status=same; else status=CHANGED; fi
  printf '%-26s %-8s %s -> %s\n' "$var" "$status" "${ref%@*}" "$current"
done
