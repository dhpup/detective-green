#!/usr/bin/env bash
# Gives every Kargo Project in this repo git credentials, so promotions can push
# rendered/* branches to your fork (pattern from akuity/akp-platform).
# Projects are discovered from apps/*/kargo/, so there's no list to maintain.
#
# Use a fine-grained GitHub token scoped to this one repo, with
# "Contents: read and write" only. Rotate it after the talk.
#
# Usage: GITHUB_USER=you hack/add-credentials.sh   (prompts for the token, hidden)
#        KARGO_GIT_TOKEN=... also works, for automation.
#
# GITHUB_TOKEN is deliberately NOT read: it's often already exported for other
# tools, and a stale one would be stored without anyone noticing.
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

user="${GITHUB_USER:-}"
token="${KARGO_GIT_TOKEN:-}"
[[ -n "$user" ]] || read -r -p "GitHub username: " user
[[ -n "$token" ]] || { read -r -s -p "GitHub token (input hidden): " token; echo; }
[[ -n "$user" && -n "$token" ]] || die "username and token are required"

repo_url="$(awk '/repoURL: https:\/\/github.com/{print $2; exit}' "${ROOT}/bootstrap/platform-aoa.yaml")"
log "repo: ${repo_url}"

# Check the token before storing it: first that GitHub accepts it at all, then
# that it can push to this repo. The push is a --dry-run to a probe branch, so
# nothing is written. The token travels in the environment, never on a
# command line.
export KARGO_GIT_USER="$user" KARGO_GIT_TOKEN="$token"
code="$(python3 - <<'PY'
import os, urllib.error, urllib.request
req = urllib.request.Request("https://api.github.com/user", headers={
    "Authorization": "Bearer " + os.environ["KARGO_GIT_TOKEN"], "User-Agent": "detective-green"})
try:
    print(urllib.request.urlopen(req, timeout=20).status)
except urllib.error.HTTPError as err:
    print(err.code)
PY
)"
[[ "$code" == 200 ]] || die "GitHub rejected the token (HTTP ${code}): expired, revoked or mistyped?"

probe="$(mktemp -d)"
trap 'rm -rf "$probe"' EXIT
git -C "$probe" init -q
git -C "$probe" -c user.name=probe -c user.email=probe@localhost commit -q --allow-empty -m probe
# shellcheck disable=SC2016 # expanded by git's credential-helper shell, not here
if ! GIT_TERMINAL_PROMPT=0 git -C "$probe" -c credential.helper= \
    -c credential.helper='!f() { echo "username=${KARGO_GIT_USER}"; echo "password=${KARGO_GIT_TOKEN}"; }; f' \
    push --dry-run -q "$repo_url" HEAD:refs/heads/rendered/credentials-probe 2>/dev/null; then
  die "the token can't push to ${repo_url}: give it Contents: read and write on this repository"
fi
log "token accepted and can push to ${repo_url}"

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
