# Helm arguments for every chart, in one place. Used by the install scripts,
# hack/verify-pins.sh and hack/verify-images.sh, so what CI checks is exactly
# what gets installed.
# shellcheck shell=bash
# shellcheck disable=SC2034 # CHARTS is used by the scripts that source this file

# chart_path <chart>: fetches (and sha256-verifies) the chart, prints its path.
chart_path() {
  case "$1" in
    cilium)        fetch_chart cilium "$CILIUM_CHART_REPO" "$CILIUM_CHART_VERSION" "$CILIUM_CHART_SHA256" ;;
    cert-manager)  fetch_chart cert-manager "$CERT_MANAGER_CHART_REPO" "$CERT_MANAGER_CHART_VERSION" "$CERT_MANAGER_CHART_SHA256" ;;
    argo-rollouts) fetch_chart argo-rollouts "$ROLLOUTS_CHART_REPO" "$ROLLOUTS_CHART_VERSION" "$ROLLOUTS_CHART_SHA256" ;;
    argo-cd)       fetch_chart argo-cd "$ARGOCD_CHART_REPO" "$ARGOCD_CHART_VERSION" "$ARGOCD_CHART_SHA256" ;;
    kargo)         fetch_chart kargo "$KARGO_CHART_OCI" "$KARGO_CHART_VERSION" "$KARGO_CHART_SHA256" ;;
    *) die "unknown chart $1" ;;
  esac
}

# chart_args <chart>: prints helm flags (one per line) that pin images and set values.
# Read them with a while-read loop (macOS ships bash 3.2, which has no mapfile).
chart_args() {
  case "$1" in
    cilium)
      printf '%s\n' --values "${ROOT}/hack/values/cilium.yaml" ;;
    cert-manager)
      printf '%s\n' --values "${ROOT}/hack/values/cert-manager.yaml" \
        --set "image.digest=${CERT_MANAGER_CONTROLLER_DIGEST}" \
        --set "webhook.image.digest=${CERT_MANAGER_WEBHOOK_DIGEST}" \
        --set "cainjector.image.digest=${CERT_MANAGER_CAINJECTOR_DIGEST}" \
        --set "startupapicheck.image.digest=${CERT_MANAGER_STARTUPAPICHECK_DIGEST}" ;;
    argo-rollouts)
      local repo; repo="$(image_repo "$ROLLOUTS_IMAGE")"
      printf '%s\n' --values "${ROOT}/hack/values/argo-rollouts.yaml" \
        --set "controller.image.registry=${repo%%/*}" \
        --set "controller.image.repository=${repo#*/}" \
        --set "controller.image.tag=$(image_tag "$ROLLOUTS_IMAGE")" ;;
    argo-cd)
      printf '%s\n' --values "${ROOT}/hack/values/argocd.yaml" \
        --set "global.image.repository=$(image_repo "$ARGOCD_IMAGE")" \
        --set "global.image.tag=$(image_tag "$ARGOCD_IMAGE")" \
        --set "redis.image.repository=$(image_repo "$ARGOCD_REDIS_IMAGE")" \
        --set "redis.image.tag=$(image_tag "$ARGOCD_REDIS_IMAGE")" ;;
    kargo)
      printf '%s\n' --values "${ROOT}/hack/values/kargo.yaml" \
        --set "image.repository=$(image_repo "$KARGO_IMAGE")" \
        --set "image.tag=$(image_tag "$KARGO_IMAGE")" ;;
    *) die "unknown chart $1" ;;
  esac
}

CHARTS=(cilium cert-manager argo-rollouts argo-cd kargo)

# rendered_images <chart>: every image the chart would deploy, as rendered.
# Placeholders only satisfy settings the install scripts pass at install time;
# they're never installed. Dies if rendering fails or finds no images, so
# callers can't mistake a broken render for "nothing unpinned".
rendered_images() {
  local args=() line out
  while IFS= read -r line; do args+=("$line"); done < <(chart_args "$1")
  case "$1" in
    cilium) args+=(--set k8sServiceHost=render-only) ;;
    kargo)  args+=(--set api.adminAccount.passwordHash=render-only --set api.adminAccount.tokenSigningKey=render-only) ;;
  esac
  out="$(helm template x "$(chart_path "$1")" "${args[@]}")" || die "helm template failed for $1"
  out="$(grep -oE 'image: *"?[^" ]+' <<<"$out" | sed -E 's/image: *"?//' | sort -u)"
  [[ -n "$out" ]] || die "chart $1 rendered no images"
  echo "$out"
}

# helm_install <chart> <release> <namespace> <kube-context> [extra helm args...]
helm_install() {
  local chart="$1" release="$2" ns="$3" context="$4" args=() line
  shift 4
  while IFS= read -r line; do args+=("$line"); done < <(chart_args "$chart")
  helm upgrade --install "$release" "$(chart_path "$chart")" \
    --kube-context "$context" --namespace "$ns" --create-namespace \
    --wait --timeout 10m "${args[@]}" "$@" >/dev/null
}
