# Shared helpers for hack/*.sh. Source it; don't run it.
# shellcheck shell=bash
# Variables here are used by the scripts that source this file.
# shellcheck disable=SC2034

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CACHE_DIR="${ROOT}/.cache"
SECRETS_DIR="${ROOT}/.secrets"
# shellcheck source=../../versions.env
source "${ROOT}/versions.env"

# Cluster names. The k3d network is shared so mgmt can reach staging/prod by
# node name (e.g. k3d-staging-server-0).
NETWORK="detective"
WORKLOAD_CLUSTERS=(staging prod)
ALL_CLUSTERS=(staging prod mgmt) # mgmt last: its CoreDNS learns the other nodes' names

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

ctx() { echo "k3d-$1"; }

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# fetch_chart <name> <repo-url|oci-ref> <version> <sha256>
# Downloads a chart into .cache/charts, verifies its sha256, and prints the path.
fetch_chart() {
  local name="$1" repo="$2" version="$3" want="$4"
  local out="${CACHE_DIR}/charts/${name}-${version}.tgz"
  mkdir -p "${CACHE_DIR}/charts"
  if [[ ! -f "$out" || "$(sha256_of "$out")" != "$want" ]]; then
    rm -f "$out"
    if [[ "$repo" == https://* ]]; then
      helm pull "$name" --repo "$repo" --version "$version" --destination "${CACHE_DIR}/charts" >/dev/null
    else
      python3 "${ROOT}/hack/lib/oci.py" pull-chart "$repo" "$version" "sha256:${want}" "$out"
    fi
  fi
  [[ "$(sha256_of "$out")" == "$want" ]] || die "chart ${name} ${version} does not match its pinned sha256"
  echo "$out"
}

# image_repo / image_tag split "repo:tag@sha256:..." for charts that take them separately.
# The tag keeps the digest ("v1.2.3@sha256:..."), so the rendered image stays pinned.
image_repo() { local ref="${1%@*}"; echo "${ref%:*}"; }
image_tag() { local ref="${1%@*}"; echo "${ref##*:}@${1#*@}"; }
# shellcheck source=charts.sh
source "${ROOT}/hack/lib/charts.sh"
