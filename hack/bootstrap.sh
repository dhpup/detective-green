#!/usr/bin/env bash
# Applies the root app-of-apps. Also creates the `live` branch from main if it
# doesn't exist yet: Kargo (kargo-apps and the Warehouses) watches `live`.
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

repo_url="$(awk '/repoURL: https:\/\/github.com/{print $2; exit}' "${ROOT}/bootstrap/platform-aoa.yaml")"
if ! git ls-remote --exit-code --heads "$repo_url" live >/dev/null 2>&1; then
  log "creating branch live from main"
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  git clone -q --depth 1 --branch main "$repo_url" "$tmp"
  git -C "$tmp" push -q origin HEAD:refs/heads/live
fi
kubectl --context "$(ctx mgmt)" apply -f "${ROOT}/bootstrap/platform-aoa.yaml"
