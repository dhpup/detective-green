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
# Default: only frontdesk -> API (uploads and requests), where the same
# sequence number going out again and again is the retransmission.
# FILTER='tcp port 8080 and host <ip>' shows both directions.
filter="${FILTER:-tcp dst port 8080 and dst host ${blue_ip}}"
# Find frontdesk's process on the node (anchored, so it can't match this very
# shell), then run tcpdump inside its network namespace.
inside="pid=\$(pgrep -f '^/case-file frontdesk' | head -1); exec nsenter -t \$pid -n"
pod=""

cleanup() {
  [[ -n "$pod" ]] && kubectl --context "$prod" delete pod "$pod" --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

# debug_pod <command>: start a node debug pod on the green node running
# <command>, wait for it to start, and print its name. Not attached: output is
# read with `kubectl logs`, which is more reliable than an interactive attach.
debug_pod() {
  local name
  name="$(kubectl --context "$prod" debug "node/${green}" --profile=sysadmin --image="$kit" -- sh -c "$1" 2>&1 \
    | sed -nE 's/.*debugging pod ([^ ]+) with.*/\1/p')"
  [[ -n "$name" ]] || die "couldn't start a debug pod on ${green}"
  kubectl --context "$prod" wait --for=jsonpath='{.status.phase}'=Running "pod/${name}" --timeout=60s >/dev/null 2>&1 || true
  echo "$name"
}

if [[ "${1:-}" == --save ]]; then
  count="${COUNT:-400}"
  file="capture-$(date +%Y%m%d-%H%M%S).pcap"
  log "capturing ${count} packets of frontdesk -> ${blue_ip}:8080 on ${green}"
  pod="$(debug_pod "${inside} tcpdump -U -s 200 -c ${count} -w /host/tmp/${file} '${FILTER:-tcp port 8080 and host ${blue_ip}}'")"
  kubectl --context "$prod" wait --for=jsonpath='{.status.phase}'=Succeeded "pod/${pod}" --timeout=300s >/dev/null \
    || die "capture didn't finish (is traffic flowing?)"
  docker cp -q "${green}:/tmp/${file}" "${ROOT}/evidence/${file}"
  docker exec "${green}" rm -f "/tmp/${file}"
  log "saved evidence/${file} ($(wc -c < "${ROOT}/evidence/${file}" | tr -d ' ') bytes); open it with evidence/wireshark-profile"
else
  say "$ tcpdump -nn '${filter}'   (inside frontdesk's netns on ${green})"
  pod="$(debug_pod "${inside} tcpdump -nn -l -c ${COUNT:-40} '${filter}'")"
  kubectl --context "$prod" logs -f "pod/${pod}"
fi
