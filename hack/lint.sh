#!/usr/bin/env bash
# Runs every pre-commit hook against the whole repo, inside the lint image.
# Hook environments are cached in a Docker volume, so only the first run is slow.
source "$(dirname "$0")/lib/common.sh"

docker build -q -t detective/lint:local "${ROOT}/hack/lint" >/dev/null
docker run --rm \
  -v "${ROOT}:/src" \
  -v detective-precommit-cache:/root/.cache/pre-commit \
  detective/lint:local run --all-files --show-diff-on-failure "$@"
