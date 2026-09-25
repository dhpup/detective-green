#!/usr/bin/env bash
# Fails if any chart doesn't match its pinned sha256, or if any image we'd
# deploy or build from isn't pinned by digest. Runs in CI on every PR.
source "$(dirname "$0")/lib/common.sh"

fail=0
check() { # check <image> <source>
  if [[ "$1" == *@sha256:* ]]; then printf '  ok       %-28s %s\n' "$2" "${1%@*}"
  else printf '  UNPINNED %-28s %s\n' "$2" "$1"; fail=1; fi
}

for chart in "${CHARTS[@]}"; do
  chart_path "$chart" >/dev/null # dies on a sha256 mismatch
  # Captured first: a failure inside <(...) wouldn't stop the script.
  images="$(rendered_images "$chart")" || exit 1
  while IFS= read -r image; do check "$image" "chart ${chart}"; done <<<"$images"
done
for var in K3S_IMAGE GO_BUILD_IMAGE DISTROLESS_STATIC_IMAGE ALPINE_IMAGE; do
  check "${!var}" "versions.env ${var}"
done

# Dockerfiles must use the same base digests as versions.env.
grep -q "ARG BASE_IMAGE=${ALPINE_IMAGE}\$" "${ROOT}/src/evidence-kit/Dockerfile" \
  || { echo "  MISMATCH src/evidence-kit/Dockerfile base != ALPINE_IMAGE"; fail=1; }

payload="${ROOT}/hack/phase0/payload/Dockerfile"
if ! grep -q "^FROM ${GO_BUILD_IMAGE} AS build\$" "$payload" \
   || ! grep -q "^FROM ${DISTROLESS_STATIC_IMAGE}\$" "$payload"; then
  echo "  MISMATCH hack/phase0/payload/Dockerfile bases != versions.env"; fail=1
fi

[[ "$fail" == 0 ]] || die "unpinned or mismatched images above"
log "all charts match their sha256 and every image is pinned by digest"
