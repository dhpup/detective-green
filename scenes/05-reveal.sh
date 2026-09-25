#!/usr/bin/env bash
# Chapter 5, the reveal: the call was coming from inside the repo.
#
#   scenes/05-reveal.sh         what reached prod, as plain rendered YAML
#   scenes/05-reveal.sh --fix   revert the culprit on live; node-network
#                               auto-promotes the fix through staging and prod
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
scene_repo

if [[ "${1:-}" == --fix ]]; then
  git_scene checkout -q -B live origin/live
  culprit="$(commit_with_subject "$CULPRIT_MSG")"
  [[ -n "$culprit" ]] || die "no culprit commit on live (run scenes/00-crime.sh first)"
  git_scene revert --no-edit "$culprit" >/dev/null
  push_live
  fix="$(git_scene rev-parse HEAD)"
  log "reverted ${culprit:0:7}: ${fix:0:7} on live"
  refresh_warehouse node-network
  nn_fix="$(freight_for node-network "$fix")"
  wait_on_stage node-network staging "$nn_fix"
  wait_on_stage node-network prod "$nn_fix"
  for n in staging-agent-1 prod-agent-1; do wait_mtu "$n" 1500; done
  say "Fixed: blue nodes back at MTU 1500 in staging and prod (Freight ${nn_fix:0:7})."
  exit 0
fi

rendered=origin/rendered/node-network/prod
say "$ git log ${rendered#origin/}"
# Subject plus the "Source: <sha> by <author>" line Kargo writes into each
# rendered commit: who really made the change.
git_scene log -3 --format='%h%x1f%ar%x1f%s%x1f%b%x1e' "$rendered" | python3 -c '
import sys
for rec in sys.stdin.read().split("\x1e"):
    if not rec.strip(): continue
    sha, when, subject, body = (rec.strip("\n").split("\x1f") + [""] * 4)[:4]
    source = next((l for l in body.splitlines() if l.startswith("Source:")), "")
    print("\033[33m%s\033[0m %s\n    %s" % (sha, when, subject))
    if source: print("    \033[2m%s\033[0m" % source)'
say "$ git show ${rendered#origin/}   (what actually reached prod)"
git_scene --no-pager show --format= --color=always "$rendered" -- '*node-tuner-blue*' | grep -E '^\S*[-+]' | grep -v -E '^\S*(\+\+\+|---)'
echo
echo "Fix it:  scenes/05-reveal.sh --fix"
