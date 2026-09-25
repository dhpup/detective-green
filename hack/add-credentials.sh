#!/usr/bin/env bash
# Gives every Kargo Project in this repo git credentials, so promotions can push
# rendered/* branches to your fork (pattern from akuity/akp-platform).
# Projects are discovered from apps/*/kargo/, so there's no list to maintain.
#
# Use a fine-grained GitHub token scoped to this one repo, with
# "Contents: read and write" only. Rotate it after the talk.
#
# Usage: GITHUB_USER=you GITHUB_TOKEN=... hack/add-credentials.sh
#        (prompts for anything not set; the token prompt is hidden)
source "$(dirname "$0")/lib/common.sh"

user="${GITHUB_USER:-}"
token="${GITHUB_TOKEN:-}"
[[ -n "$user" ]] || read -r -p "GitHub username: " user
[[ -n "$token" ]] || { read -r -s -p "GitHub token (input hidden): " token; echo; }
[[ -n "$user" && -n "$token" ]] || die "username and token are required"

repo_url="$(awk '/repoURL: https:\/\/github.com/{print $2; exit}' "${ROOT}/bootstrap/platform-aoa.yaml")"
log "repo: ${repo_url}"

found=0
for dir in "${ROOT}"/apps/*/kargo; do
  [[ -d "$dir" ]] || continue
  project="$(basename "$(dirname "$dir")")"; found=1
  if ! kubectl --context "$(ctx mgmt)" get namespace "$project" >/dev/null 2>&1; then
    log "skipping ${project}: Kargo Project not created yet (run 'make bootstrap' first)"
    continue
  fi
  # Piped in on stdin so the token never appears in process arguments.
  kubectl --context "$(ctx mgmt)" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: github-creds
  namespace: ${project}
  labels: {kargo.akuity.io/cred-type: git}
type: Opaque
stringData:
  repoURL: ${repo_url}
  username: ${user}
  password: ${token}
YAML
  log "${project}: github-creds set"
done
[[ "$found" == 1 ]] || log "no apps/*/kargo directories yet; nothing to do"
