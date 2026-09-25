#!/usr/bin/env bash
# Go checks for src/case-file, run in the pinned Go and golangci-lint images
# (the same versions CI uses). Module and build caches live in Docker volumes.
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

src="${ROOT}/src/case-file"
caches=(-v detective-gomod:/go/pkg/mod -v detective-gobuild:/root/.cache)

log "go vet + go test -race + govulncheck"
docker run --rm -v "${src}:/src" -w /src "${caches[@]}" "$GO_BUILD_IMAGE" sh -ec "
  go vet ./...
  go test -race -count=1 -timeout 120s ./...
  go run golang.org/x/vuln/cmd/govulncheck@${GOVULNCHECK_VERSION} ./..."

log "golangci-lint"
docker run --rm -v "${src}:/src" -w /src "${caches[@]}" "$GOLANGCI_LINT_IMAGE" golangci-lint run ./...
