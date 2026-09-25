# Shared helpers for scenes/*.sh. Source it; don't run it.
# shellcheck shell=bash
# Variables here are used by the scripts that source this file.
# shellcheck disable=SC2034
# shellcheck source=../hack/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../hack/lib/common.sh"

# The scenes commit to the `live` branch, in their own clone under .cache/, so
# they never touch your working tree. Pushing uses your normal git credentials.
SCENE_REPO="${CACHE_DIR}/scene-repo"
REPO_URL="$(awk '/repoURL: https:\/\/github.com/{print $2; exit}' "${ROOT}/bootstrap/platform-aoa.yaml")"
IMAGE="$(sed -E 's#https://github.com/([^/]+)/.*#ghcr.io/\1/case-file#' <<<"$REPO_URL" | tr '[:upper:]' '[:lower:]')"
CULPRIT_MSG="platform: align blue-pool underlay MTU with new fabric (1450)"
# Fictional platform-team identity for the scene's platform commits.
CULPRIT_AUTHOR_NAME="Platform Team"
CULPRIT_AUTHOR_EMAIL="platform-team@detective-green.example"

git_scene() { git -C "$SCENE_REPO" "$@"; }

# scene_repo: make sure the clone exists and is up to date.
scene_repo() {
  if [[ ! -d "${SCENE_REPO}/.git" ]]; then
    git clone -q "$REPO_URL" "$SCENE_REPO"
  fi
  git_scene fetch -q --prune origin '+refs/heads/*:refs/remotes/origin/*'
}

push_live() { git_scene push -q --force-with-lease origin HEAD:refs/heads/live; }

# changelog <line>: append to apps/node-network/CHANGELOG.md (not rendered).
changelog() {
  local f="${SCENE_REPO}/apps/node-network/CHANGELOG.md"
  [[ -f "$f" ]] || printf '# node-network changelog\n\n' > "$f"
  printf -- '- %s: %s\n' "$(date -u +%Y-%m-%dT%H:%MZ)" "$1" >> "$f"
}

# platform_commit <message>: commit everything staged under apps/node-network
# as the (fictional) platform team.
platform_commit() {
  git_scene add apps/node-network
  GIT_AUTHOR_NAME="$CULPRIT_AUTHOR_NAME" GIT_AUTHOR_EMAIL="$CULPRIT_AUTHOR_EMAIL" \
  GIT_COMMITTER_NAME="$CULPRIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$CULPRIT_AUTHOR_EMAIL" \
    git_scene commit -q -m "$1"
}

# kargo_cli: the Kargo CLI, logged in as the lab admin.
kargo_cli() {
  if ! kargo get projects >/dev/null 2>&1; then
    kargo login https://localhost:8444 --admin --password "$(cat "${SECRETS_DIR}/kargo-admin-password")" \
      --insecure-skip-tls-verify >/dev/null
  fi
  kargo "$@"
}

refresh_warehouse() { kargo_cli refresh warehouse "$1" --project "$1" >/dev/null; }

# freight_for <project> <commit> [image-tag]: waits for Freight with that commit
# (and image tag, for case-file) and prints its name.
freight_for() {
  local project="$1" commit="$2" tag="${3:-}" name=""
  for _ in $(seq 1 60); do
    name="$(kubectl --context "$(ctx mgmt)" -n "$project" get freight -o json | COMMIT="$commit" TAG="$tag" python3 -c '
import json, os, sys
for f in json.load(sys.stdin)["items"]:
    commits = [c["id"] for c in f.get("commits", [])]
    tags = [i["tag"] for i in f.get("images", [])]
    if os.environ["COMMIT"] in commits and (not os.environ["TAG"] or os.environ["TAG"] in tags):
        print(f["metadata"]["name"]); break')"
    [[ -n "$name" ]] && { echo "$name"; return; }
    sleep 3
  done
  die "no ${project} Freight appeared for ${commit:0:7} ${tag}"
}

# commit_with_subject <subject>: newest commit on HEAD with exactly this subject.
commit_with_subject() {
  git_scene log --format='%H%x09%s' | SUBJECT="$1" python3 -c '
import os, sys
for line in sys.stdin:
    sha, _, subject = line.rstrip("\n").partition("\t")
    if subject == os.environ["SUBJECT"]:
        print(sha); break'
}

# last_verification <project> <stage>: "<phase> <analysisrun>" for the Stage's
# current Freight, from the Stage's own verification history.
last_verification() {
  kubectl --context "$(ctx mgmt)" -n "$1" get stage "$2" -o json | python3 -c '
import json, sys
hist = (json.load(sys.stdin).get("status", {}).get("freightHistory") or [{}])[0].get("verificationHistory") or []
if hist:
    v = hist[0]
    print(v.get("phase", ""), (v.get("analysisRun") or {}).get("name", ""))'
}

current_freight() {
  kubectl --context "$(ctx mgmt)" -n "$1" get stage "$2" -o jsonpath='{.status.freightHistory[0].items.*.name}'
}

# promote <project> <stage> <freight>: promote unless the Stage already has it,
# then wait for the promotion to finish.
promote() {
  local project="$1" stage="$2" freight="$3" phase
  [[ "$(current_freight "$project" "$stage")" == "$freight" ]] && return 0
  kargo_cli promote --project "$project" --stage "$stage" --freight "$freight" >/dev/null
  wait_on_stage "$project" "$stage" "$freight"
}

# wait_on_stage <project> <stage> <freight>: until the Stage's current Freight is
# <freight> (promoted by us or by auto-promotion) and its last promotion succeeded.
wait_on_stage() {
  local project="$1" stage="$2" freight="$3"
  for _ in $(seq 1 90); do
    if [[ "$(current_freight "$project" "$stage")" == "$freight" ]]; then return 0; fi
    local last
    last="$(kubectl --context "$(ctx mgmt)" -n "$project" get promotions -o json | STAGE="$stage" FREIGHT="$freight" python3 -c '
import json, os, sys
ps = [p for p in json.load(sys.stdin)["items"] if p["spec"]["stage"] == os.environ["STAGE"] and p["spec"]["freight"] == os.environ["FREIGHT"]]
ps.sort(key=lambda p: p["metadata"]["creationTimestamp"])
print(ps[-1].get("status", {}).get("phase", "") if ps else "")')"
    [[ "$last" == Errored || "$last" == Failed ]] && die "${project}/${stage}: promotion of ${freight:0:7} ${last}"
    sleep 3
  done
  die "${project}/${stage}: timed out waiting for ${freight:0:7}"
}

# verified_in <project> <freight> <stage>: true if the Freight was ever verified there.
verified_in() {
  kubectl --context "$(ctx mgmt)" -n "$1" get freight "$2" -o jsonpath="{.status.verifiedIn.$3}" | grep -q .
}

# wait_verified <project> <freight> <stage> <seconds>
wait_verified() {
  for _ in $(seq 1 $(( $4 / 5 ))); do verified_in "$1" "$2" "$3" && return 0; sleep 5; done
  return 1
}

node_mtu() { docker exec "k3d-$1" cat /sys/class/net/eth0/mtu; }

# wait_mtu <node> <mtu>: e.g. wait_mtu prod-agent-1 1450
wait_mtu() {
  for _ in $(seq 1 60); do [[ "$(node_mtu "$1")" == "$2" ]] && return 0; sleep 2; done
  die "k3d-$1 eth0 never reached MTU $2"
}

# refresh_app <argocd-app>: ask Argo CD to re-read git now.
refresh_app() {
  kubectl --context "$(ctx mgmt)" -n argocd annotate application "$1" argocd.argoproj.io/refresh=hard --overwrite >/dev/null
}

say() { printf '\n\033[1;33m%s\033[0m\n' "$*"; }
