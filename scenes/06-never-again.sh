#!/usr/bin/env bash
# Chapter 6, never again: the pipeline becomes the detective.
#
#   1. Merge scene-6/gate-the-platform into live: node-network's staging Stage
#      gets the same shared checks as case-file.
#   2. Re-push the culprit (revert the revert).
#   3. Kargo auto-promotes it to staging, where the gate runs...
#   4. ...and fails.
#   5. prod never gets it: the Freight isn't verified, so it isn't eligible.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
scene_repo
git_scene checkout -q -B live origin/live
start=$(date +%s)

say "1/5  Merging the gate: scene-6/gate-the-platform -> live"
git_scene merge -q --no-ff -m "Merge branch 'scene-6/gate-the-platform': gate node-network on the app's checks" \
  origin/scene-6/gate-the-platform
push_live
refresh_app kargo-node-network
for _ in $(seq 1 60); do
  v="$(kubectl --context "$(ctx mgmt)" -n node-network get stage staging -o jsonpath='{.spec.verification.analysisTemplates[*].name}')"
  [[ -n "$v" ]] && break
  sleep 2
done
[[ -n "$v" ]] || die "node-network staging never picked up the verification"
log "node-network staging now verifies with: ${v}"
prod_before="$(current_freight node-network prod)"

say "2/5  Re-pushing the culprit"
fix="$(commit_with_subject "Revert \"${CULPRIT_MSG}\"")"
[[ -n "$fix" ]] || die "no revert of the culprit on live (run scenes/05-reveal.sh --fix first)"
git_scene revert --no-edit "$fix" >/dev/null
push_live
bad="$(git_scene rev-parse HEAD)"
log "${bad:0:7}: $(git_scene log -1 --format=%s)"

say "3/5  Kargo promotes it to staging"
refresh_warehouse node-network
nn_bad="$(freight_for node-network "$bad")"
wait_on_stage node-network staging "$nn_bad"
wait_mtu staging-agent-1 1450
log "staging has ${nn_bad:0:7}; blue node at MTU 1450"

say "4/5  The gate runs"
verdict=""
for _ in $(seq 1 90); do
  verdict="$(last_verification node-network staging)"
  case "$verdict" in Failed*|Error*|Successful*|Inconclusive*) break ;; esac
  sleep 4
done
read -r phase run <<<"$verdict"
log "verification: ${phase:-none} (AnalysisRun ${run:-?})"
job="$(kubectl --context "$(ctx mgmt)" -n node-network get jobs --sort-by=.metadata.creationTimestamp -o name | tail -1)"
[[ -n "$job" ]] && kubectl --context "$(ctx mgmt)" -n node-network logs "$job" 2>/dev/null | grep -E "^(FAIL|RESULT)" | head -4

say "5/5  prod"
if verified_in node-network "$nn_bad" staging; then
  die "the bad Freight was verified in staging: the gate did not catch it"
fi
sleep 15
prod_after="$(current_freight node-network prod)"
[[ "$prod_after" == "$prod_before" ]] || die "prod changed to ${prod_after:0:7}: the gate did not hold"
log "prod still on ${prod_after:0:7}; ${nn_bad:0:7} is not verified, so it's not eligible for prod"
say "Caught before prod. ($(( $(date +%s) - start ))s)"
