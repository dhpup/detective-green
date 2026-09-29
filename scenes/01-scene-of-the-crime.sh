#!/usr/bin/env bash
# Chapter 1, the scene of the crime: why every check is green.
# Shows frontdesk's probes, then what they actually ask for (/healthz, 2 bytes)
# next to what users send (1 MB uploads), all against prod.
#
#   scenes/01-scene-of-the-crime.sh           default: 6 uploads
#   UPLOADS=10 scenes/01-scene-of-the-crime.sh
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

prod="$(ctx prod)"
ns=case-file-prod
node="$(kubectl --context "$prod" -n "$ns" get pod -l app=frontdesk -o jsonpath='{.items[0].spec.nodeName}')"
[[ -n "$node" ]] || die "frontdesk isn't running in prod (run 'make reset' first)"

# frontdesk's NodePort, straight from the host where the Docker runtime routes
# to container IPs (OrbStack, Linux); otherwise through a port-forward.
ip="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$node")"
url="http://${ip}:30080"
if ! curl -s -m 2 -o /dev/null "${url}/healthz"; then
  kubectl --context "$prod" -n "$ns" port-forward svc/frontdesk 18080:8080 >/dev/null 2>&1 &
  pf=$!
  trap 'kill "$pf" 2>/dev/null' EXIT
  url="http://localhost:18080"
  for _ in $(seq 1 20); do curl -s -m 1 -o /dev/null "${url}/healthz" && break; sleep 0.5; done
fi

say "$ kubectl get deploy frontdesk -o yaml   (the probes)"
kubectl --context "$prod" -n "$ns" get deploy frontdesk -o json | python3 -c '
import json, sys
c = json.load(sys.stdin)["spec"]["template"]["spec"]["containers"][0]
for kind in ("readinessProbe", "livenessProbe"):
    g = c[kind]["httpGet"]
    print("  %-15s GET %s on port %s" % (kind + ":", g["path"], g["port"]))'

say "$ curl ${url}/healthz   (what Kubernetes asks)"
curl -s -m 5 -o /dev/null -w '  HTTP %{http_code}, %{size_download} bytes, %{time_total}s\n' "${url}/healthz"

say "$ curl --data-binary @1MB ${url}/api/evidence   (what users send)"
for i in $(seq 1 "${UPLOADS:-6}"); do
  head -c 1048576 /dev/zero \
    | curl -s -m 10 -o /dev/null -w "  upload ${i}: HTTP %{http_code} in %{time_total}s\n" --data-binary @- "${url}/api/evidence" \
    || echo "  upload ${i}: no response"
done
echo
echo "The probe asks for 2 bytes. The users send a megabyte."
