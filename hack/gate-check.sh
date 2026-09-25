#!/usr/bin/env bash
# Runs the promotion gate right now, outside Kargo: builds one AnalysisRun from
# the shared ClusterAnalysisTemplates (the same ones staging's verification
# uses), waits for it, and prints each check's result. On failure it also
# prints the payload sweep's failed requests.
#
# Usage: hack/gate-check.sh [namespace]   (default: case-file)
# Exit code: 0 if the gate passes, 1 if it fails.
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

ns="${1:-case-file}"
mgmt="$(ctx mgmt)"
name="gate-check-$(date +%s)"

TEMPLATES="$(kubectl --context "$mgmt" get clusteranalysistemplate payload-sweep network-signals -o json)" \
python3 - "$name" "$ns" <<'PY' | kubectl --context "$mgmt" create -f - >/dev/null
import json, os, sys
name, ns = sys.argv[1], sys.argv[2]
items = json.loads(os.environ["TEMPLATES"])["items"]
run = {"apiVersion": "argoproj.io/v1alpha1", "kind": "AnalysisRun",
       "metadata": {"name": name, "namespace": ns, "labels": {"detective/gate-check": "true"}},
       "spec": {"args": [], "metrics": []}}
for t in items:
    run["spec"]["args"] += t["spec"].get("args", [])
    run["spec"]["metrics"] += t["spec"]["metrics"]
print(json.dumps(run))
PY
log "running ${name} in ${ns} (takes ~90s)"

for _ in $(seq 1 60); do
  phase="$(kubectl --context "$mgmt" -n "$ns" get analysisrun "$name" -o jsonpath='{.status.phase}')"
  case "$phase" in Successful|Failed|Error|Inconclusive) break ;; esac
  sleep 5
done

kubectl --context "$mgmt" -n "$ns" get analysisrun "$name" -o json | python3 -c '
import json, sys
run = json.load(sys.stdin)
for m in run["status"].get("metricResults", []):
    last = (m.get("measurements") or [{}])[-1]
    print("  %-22s %-11s %s" % (m["name"], m.get("phase"), last.get("value", last.get("message", ""))))'

if [[ "$phase" != Successful ]]; then
  job="$(kubectl --context "$mgmt" -n "$ns" get jobs -l "analysisrun.argoproj.io/uid=$(kubectl --context "$mgmt" -n "$ns" get analysisrun "$name" -o jsonpath='{.metadata.uid}')" -o name | head -1)"
  if [[ -n "$job" ]]; then
    echo "  payload-sweep failures:"
    kubectl --context "$mgmt" -n "$ns" logs "$job" 2>/dev/null | grep -E "^(FAIL|RESULT)" | sed 's/^/    /' | head -8
  fi
  echo "GATE: ${phase:-timed out}"
  exit 1
fi
echo "GATE: Successful"
