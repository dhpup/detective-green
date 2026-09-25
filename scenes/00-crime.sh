#!/usr/bin/env bash
# Pre-talk: put the world into the "2am" state, from whatever state it's in.
# This is `make reset`. Safe to run any number of times.
#
#   1. Rebuild the `live` branch from main (drops the last run's culprit, fix
#      and Chapter 6 gate merge), plus a baseline platform commit. Kargo
#      auto-promotes the NEWEST Freight, so each reset needs fresh Freight that
#      is newer than the last run's culprit. The commit only touches
#      apps/node-network/CHANGELOG.md, which isn't rendered.
#   2. Baseline: node-network at MTU 1500 and case-file v1.3.0 (the release
#      that shipped the same night) in both clusters.
#   3. The night: a platform commit lowers the blue pool's MTU. node-network
#      has no gate, so it auto-promotes straight through staging and prod.
#
# Afterwards: every Argo CD app is Synced/Healthy, and prod's users are failing.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
start=$(date +%s)

say "1/3  Rebuilding live from main"
scene_repo
git_scene checkout -q -B live origin/main
changelog "node-tuner: green and blue pools at MTU 1500"
platform_commit "platform: pin node-tuner MTU to 1500 on both pools"
push_live
base="$(git_scene rev-parse HEAD)"
log "live = main + baseline ${base:0:7}"
# kargo-apps tracks live: make Argo CD drop any Chapter 6 gate right away, and
# wait until it has. Otherwise the baseline would still have to pass the gate.
refresh_app kargo-node-network
refresh_app kargo-case-file
for _ in $(seq 1 60); do
  gate="$(kubectl --context "$(ctx mgmt)" -n node-network get stage staging -o jsonpath='{.spec.verification}')"
  [[ -z "$gate" ]] && break
  sleep 2
done
[[ -z "$gate" ]] || die "node-network staging still has the Chapter 6 gate (Argo CD hasn't synced live yet)"

say "2/3  Baseline: node-network at MTU 1500, case-file v1.3.0"
refresh_warehouse node-network
nn_base="$(freight_for node-network "$base")"
promote node-network staging "$nn_base"
promote node-network prod "$nn_base"
for n in staging-agent-1 prod-agent-1; do wait_mtu "$n" 1500; done
log "node-network ${nn_base:0:7} in staging and prod; blue nodes at MTU 1500"

# case-file staging auto-promotes the newest Freight; prod is promoted by hand,
# and only takes Freight that passed staging's gate.
# The Warehouse only sees commits that touch apps/case-file (includePaths),
# so the Freight's commit is the newest of those, not the tip of live.
refresh_warehouse case-file
cf_commit="$(git_scene log -1 --format=%H -- apps/case-file)"
cf="$(freight_for case-file "$cf_commit" v1.3.0)"
wait_on_stage case-file staging "$cf"
wait_verified case-file "$cf" staging 240 || die "case-file ${cf:0:7} failed verification in staging"
promote case-file prod "$cf"
log "case-file v1.3.0 (${cf:0:7}) in staging and prod, verified"

say "3/3  The night: the platform commit"
sed -i.bak 's/--mtu=1500/--mtu=1450/' "${SCENE_REPO}/apps/node-network/base/node-tuner-blue.yaml"
rm -f "${SCENE_REPO}/apps/node-network/base/node-tuner-blue.yaml.bak"
changelog "node-tuner: blue pool to MTU 1450 to match the new fabric"
platform_commit "$CULPRIT_MSG"
push_live
culprit="$(git_scene rev-parse HEAD)"
log "pushed ${culprit:0:7} \"${CULPRIT_MSG}\""
refresh_warehouse node-network
nn_bad="$(freight_for node-network "$culprit")"
wait_on_stage node-network staging "$nn_bad"
wait_on_stage node-network prod "$nn_bad"
for n in staging-agent-1 prod-agent-1; do wait_mtu "$n" 1450; done
log "node-network ${nn_bad:0:7} auto-promoted to staging and prod; blue nodes at MTU 1450"

# Wait for Argo CD to finish rolling node-tuner out, so the table is all green.
for _ in $(seq 1 30); do
  kubectl --context "$(ctx mgmt)" -n argocd get applications --no-headers \
    | awk '$1 ~ /^(case-file|node-network|informant)-/ && ($2 != "Synced" || $3 != "Healthy")' | grep -q . || break
  sleep 2
done

say "It's 2am. ($(( $(date +%s) - start ))s)"
kubectl --context "$(ctx mgmt)" -n argocd get applications -o custom-columns='APP:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status' \
  | grep -E "APP|case-file-|node-network-|informant-"
echo
echo "Everything is Synced and Healthy. Now open http://localhost:3002 (prod's Precinct Board)."
