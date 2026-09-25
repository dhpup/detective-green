#!/usr/bin/env bash
# Builds our images locally as detective/<name>:local and scans them with the
# pinned Trivy image, failing on fixable HIGH/CRITICAL (same gate as CI).
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

build() { # build <name> <base-image>
  log "building detective/$1:local"
  docker build -q --build-arg VERSION=local --build-arg GO_IMAGE="$GO_BUILD_IMAGE" \
    --build-arg BASE_IMAGE="$2" -t "detective/$1:local" "${ROOT}/src/$1" >/dev/null
  log "scanning detective/$1:local"
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v detective-trivy-cache:/root/.cache \
    -v "${ROOT}/.trivyignore.yaml:/.trivyignore.yaml:ro" "$TRIVY_IMAGE" \
    image --quiet --exit-code 1 --ignore-unfixed --severity CRITICAL,HIGH \
    --ignorefile /.trivyignore.yaml "detective/$1:local"
}

build case-file "$DISTROLESS_STATIC_IMAGE"
build evidence-kit "$ALPINE_IMAGE"
log "images built and clean"
