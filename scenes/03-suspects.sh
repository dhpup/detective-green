#!/usr/bin/env bash
# Chapter 3, the suspects: is it a network policy? DNS?
# Asks Hubble, on frontdesk's (green) node in prod, about frontdesk's traffic:
# the flows to the API pod on the blue node are FORWARDED, DNS answers, and
# nothing is DROPPED. The packets leave; something below Hubble loses them.
#
# Queries the green node's Cilium agent on purpose: while the blue node is
# broken, `kubectl exec` into anything on it hangs (see 04-capture.sh).
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

prod="$(ctx prod)"
ns=case-file-prod
frontdesk="$(kubectl --context "$prod" -n "$ns" get pod -l app=frontdesk -o jsonpath='{.items[0].metadata.name}')"
[[ -n "$frontdesk" ]] || die "frontdesk isn't running in prod (run 'make reset' first)"
green="$(kubectl --context "$prod" -n "$ns" get pod "$frontdesk" -o jsonpath='{.spec.nodeName}')"
blue_api="$(kubectl --context "$prod" -n "$ns" get pod -l app=evidence-locker -o json | python3 -c '
import json, sys
for p in json.load(sys.stdin)["items"]:
    if p["spec"]["nodeName"].endswith("agent-1"): print(p["metadata"]["name"])')"
[[ -n "$blue_api" ]] || die "no evidence-locker pod on the blue node"
agent="$(kubectl --context "$prod" -n kube-system get pod -l k8s-app=cilium --field-selector "spec.nodeName=${green}" -o name)"

hubble() { kubectl --context "$prod" -n kube-system exec "$agent" -c cilium-agent -- hubble observe "$@"; }

say "Suspect 1, a network policy: $ hubble observe --from-pod ${ns}/frontdesk --to-pod ${ns}/${blue_api}"
hubble --from-pod "${ns}/${frontdesk}" --to-pod "${ns}/${blue_api}" --last "${LAST:-6}" -o compact

say "Every flow from frontdesk that Hubble still remembers, by verdict"
hubble --from-pod "${ns}/${frontdesk}" --last 5000 -o json | python3 -c '
import collections, json, sys
seen = collections.Counter(json.loads(l).get("flow", {}).get("verdict", "?") for l in sys.stdin if l.strip())
for verdict in ("FORWARDED", "DROPPED"):
    print("  %-10s %d" % (verdict, seen.pop(verdict, 0)))
for verdict, n in seen.items():
    print("  %-10s %d" % (verdict, n))'

say "Suspect 2, DNS: $ hubble observe --from-pod ${ns}/frontdesk --port 53"
hubble --from-pod "${ns}/${frontdesk}" --port 53 --last 4 -o compact
echo
echo "Forwarded, not dropped, and DNS answers. The packets leave; somewhere below, they vanish."
