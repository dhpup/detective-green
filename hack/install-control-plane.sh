#!/usr/bin/env bash
# Installs the open-source control plane into the mgmt cluster:
# cert-manager -> Argo Rollouts -> Argo CD -> Kargo.
# Charts are verified against their pinned sha256 and every image is pinned by
# digest (versions.env, hack/lib/charts.sh).
source "$(dirname "$0")/lib/common.sh"

mgmt="$(ctx mgmt)"

log "installing cert-manager ${CERT_MANAGER_CHART_VERSION}"
helm_install cert-manager cert-manager cert-manager "$mgmt"
log "installing Argo Rollouts (chart ${ROLLOUTS_CHART_VERSION})"
helm_install argo-rollouts argo-rollouts argo-rollouts "$mgmt"
log "installing Argo CD (chart ${ARGOCD_CHART_VERSION})"
helm_install argo-cd argocd argocd "$mgmt"

# Kargo admin credentials: generated once into .secrets/ (gitignored). The
# bcrypt hash is stored too, so re-runs pass the same value and don't roll Kargo.
mkdir -p "$SECRETS_DIR" && chmod 700 "$SECRETS_DIR"
if [[ ! -f "${SECRETS_DIR}/kargo-admin-password-hash" ]]; then
  password="$(openssl rand -base64 18 | tr -d '\n')"
  printf '%s' "$password" > "${SECRETS_DIR}/kargo-admin-password"
  htpasswd -nbBC 10 "" "$password" | tr -d ':\n' > "${SECRETS_DIR}/kargo-admin-password-hash"
  openssl rand -base64 48 | tr -d '\n' > "${SECRETS_DIR}/kargo-token-signing-key"
  chmod 600 "${SECRETS_DIR}"/kargo-*
fi

log "installing Kargo ${KARGO_CHART_VERSION}"
helm_install kargo kargo kargo "$mgmt" \
  --set-string api.adminAccount.passwordHash="$(cat "${SECRETS_DIR}/kargo-admin-password-hash")" \
  --set-string api.adminAccount.tokenSigningKey="$(cat "${SECRETS_DIR}/kargo-token-signing-key")"

log "control plane ready"
