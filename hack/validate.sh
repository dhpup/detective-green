#!/usr/bin/env bash
# Validates every manifest in the repo with kubeconform (-strict), using JSON
# schemas for our CRDs from the pinned CRDs-catalog commit:
#   - each apps/*/env/<stage> overlay, rendered with kustomize
#   - every argocd/, kargo/, bootstrap/ and kargo-shared/ manifest as-is
# kustomize and kubeconform run via `go run <module>@<version>` in the pinned
# Go image (same as CI). Module caches live in Docker volumes.
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

docker run --rm -v "${ROOT}:/src:ro" -w /src \
  -v detective-gomod:/go/pkg/mod -v detective-gobuild:/root/.cache \
  -e KUSTOMIZE_VERSION="$KUSTOMIZE_VERSION" -e KUBECONFORM_VERSION="$KUBECONFORM_VERSION" \
  -e CRDS_CATALOG_REF="$CRDS_CATALOG_REF" \
  "$GO_BUILD_IMAGE" sh -ec '
  out=/tmp/manifests; mkdir -p "$out"
  kustomize="go run sigs.k8s.io/kustomize/kustomize/v5@${KUSTOMIZE_VERSION}"
  for overlay in apps/*/env/*/; do
    [ -f "${overlay}kustomization.yaml" ] || continue
    $kustomize build "$overlay" > "$out/$(echo "${overlay%/}" | tr / _).yaml"
  done
  for f in bootstrap/*.yaml apps/*/argocd/*.yaml apps/*/kargo/*.yaml kargo-shared/*.yaml; do
    [ -f "$f" ] && cp "$f" "$out/$(echo "$f" | tr / _)"
  done
  go run "github.com/yannh/kubeconform/cmd/kubeconform@${KUBECONFORM_VERSION}" \
    -strict -summary -output text \
    -schema-location default \
    -schema-location "https://raw.githubusercontent.com/datreeio/CRDs-catalog/${CRDS_CATALOG_REF}/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json" \
    "$out"'
