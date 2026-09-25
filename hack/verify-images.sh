#!/usr/bin/env bash
# Checks every pinned image:
#   1. cosign signature, for publishers that sign keyless via GitHub or Google
#   2. Trivy scan: fails on fixable CRITICAL vulnerabilities, reports HIGH.
#      Documented, expiring exceptions live in .trivyignore.yaml.
# Needs cosign and trivy. Run weekly in CI and whenever versions.env changes.
source "$(dirname "$0")/lib/common.sh"

command -v cosign >/dev/null || die "cosign not found"
command -v trivy >/dev/null || die "trivy not found"

# Every image here is public, so pull anonymously. Using the local Docker config
# can pop up (or hang on) OS keychain prompts, and a stale GITHUB_TOKEN breaks
# ghcr.io pulls.
DOCKER_CONFIG="$(mktemp -d)"; export DOCKER_CONFIG
echo '{}' > "${DOCKER_CONFIG}/config.json"
trap 'rm -rf "$DOCKER_CONFIG"' EXIT
unset GITHUB_TOKEN

GH_ISSUER=https://token.actions.githubusercontent.com
# signer <image>: prints "<identity-regexp> <issuer>" for publishers we know sign.
signer() {
  case "$1" in
    quay.io/argoproj/argocd*)       echo "^https://github.com/argoproj/argo-cd/ $GH_ISSUER" ;;
    quay.io/argoproj/argo-rollouts*) echo "^https://github.com/argoproj/argo-rollouts/ $GH_ISSUER" ;;
    quay.io/cilium/cilium-envoy*)   echo "^https://github.com/cilium/proxy/ $GH_ISSUER" ;;
    quay.io/cilium/*)               echo "^https://github.com/cilium/cilium/ $GH_ISSUER" ;;
    ghcr.io/akuity/kargo*)          echo "^https://github.com/akuity/kargo/ $GH_ISSUER" ;;
    gcr.io/distroless/*)            echo "^keyless@distroless.iam.gserviceaccount.com\$ https://accounts.google.com" ;;
    *) ;;
  esac
}

images=()
for chart in "${CHARTS[@]}"; do
  rendered="$(rendered_images "$chart")" || exit 1
  while IFS= read -r image; do images+=("$image"); done <<<"$rendered"
done
images+=("$K3S_IMAGE" "$GO_BUILD_IMAGE" "$DISTROLESS_STATIC_IMAGE" "$ALPINE_IMAGE")

fail=0
printf '%-62s %-10s %s\n' IMAGE SIGNATURE "FIXABLE CRIT/HIGH"
for image in "${images[@]}"; do
  sig="n/a"
  read -r identity issuer <<<"$(signer "$image")" || true
  if [[ -n "${identity:-}" ]]; then
    if cosign verify --certificate-identity-regexp "$identity" --certificate-oidc-issuer "$issuer" \
         "$image" >/dev/null 2>&1; then sig="verified"; else sig="FAILED"; fail=1; fi
  fi
  counts="$(trivy image --quiet --ignore-unfixed --ignorefile "${ROOT}/.trivyignore.yaml" --severity CRITICAL,HIGH --format json "$image" 2>/dev/null \
    | python3 -c 'import sys,json
r=json.load(sys.stdin).get("Results") or []
v=[x["Severity"] for t in r for x in (t.get("Vulnerabilities") or [])]
print(v.count("CRITICAL"), v.count("HIGH"))' 2>/dev/null || echo "? ?")"
  read -r crit high <<<"$counts"
  [[ "$crit" == "?" || "$crit" -gt 0 ]] && fail=1
  printf '%-62s %-10s %s/%s\n' "${image%@*}" "$sig" "$crit" "$high"
  identity=""
done

[[ "$fail" == 0 ]] || die "a signature failed or a fixable CRITICAL vulnerability was found (see above)"
log "all signatures verified where published; no fixable CRITICAL vulnerabilities"
