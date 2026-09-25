#!/usr/bin/env bash
# Chapter 4: the packets don't lie. Captures frontdesk's uploads to the API pod
# on the blue node, in prod, from inside frontdesk's network namespace.
#
# The capture runs from a debug pod on the GREEN node (where frontdesk is):
# while the blue node is broken, the API server's own connections to blue's
# kubelet fall into the same black hole, so `kubectl debug node/<blue>` hangs.
#
#   scenes/04-capture.sh          live text: watch the retransmissions happen
#   scenes/04-capture.sh --save   write evidence/capture-<time>.pcap for Wireshark
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

prod="$(ctx prod)"
ns=case-file-prod
green="$(kubectl --context "$prod" -n "$ns" get pod -l app=frontdesk -o jsonpath='{.items[0].spec.nodeName}')"
blue_ip="$(kubectl --context "$prod" -n "$ns" get pod -l app=evidence-locker -o json | python3 -c '
import json, sys
for p in json.load(sys.stdin)["items"]:
    if p["spec"]["nodeName"].endswith("agent-1"): print(p["status"]["podIP"])')"
[[ -n "$green" && -n "$blue_ip" ]] || die "couldn't find frontdesk and the blue API pod in ${ns}"
kit="${IMAGE/case-file/evidence-kit}:v1.2.0"
filter="tcp port 8080 and host ${blue_ip}"
# Find frontdesk's process on the node, then run tcpdump in its network namespace.
inside="pid=\$(pgrep -f 'case-file frontdesk' | head -1); exec nsenter -t \$pid -n"

cleanup() {
  kubectl --context "$prod" get pods -o name 2>/dev/null | grep "node-debugger-${green}" \
    | xargs -r kubectl --context "$prod" delete --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

if [[ "${1:-}" == --save ]]; then
  out="${ROOT}/evidence/capture-$(date +%Y%m%d-%H%M%S).pcap"
  log "capturing ${COUNT:-400} packets of frontdesk -> ${blue_ip}:8080 into ${out#"${ROOT}"/}"
  kubectl --context "$prod" debug "node/${green}" -q -i --profile=sysadmin --image="$kit" -- \
    sh -c "${inside} tcpdump -U -s 200 -c ${COUNT:-400} -w - '${filter}' 2>/dev/null" > "$out"
  log "saved $(wc -c < "$out" | tr -d ' ') bytes; open it in Wireshark with evidence/wireshark-profile"
else
  say "$ tcpdump -nn '${filter}'   (inside frontdesk's netns on ${green})"
  kubectl --context "$prod" debug "node/${green}" -q -i --profile=sysadmin --image="$kit" -- \
    sh -c "${inside} tcpdump -nn -l -c ${COUNT:-40} '${filter}'"
fi
