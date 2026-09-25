#!/usr/bin/env bash
# Run one payload sweep from a client pod on the green node to the server on <pool>.
set -euo pipefail
ctx="${CTX:-k3d-phase0}"
dst="${1:-blue}"
ip=$(kubectl --context "$ctx" -n phase0 get pod "server-$dst" -o jsonpath='{.status.podIP}')
name="sweep-$(date +%s)-$RANDOM"
overrides=$(cat <<JSON
{"spec":{"nodeSelector":{"pool":"green"},"restartPolicy":"Never",
 "securityContext":{"runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}},
 "containers":[{"name":"sweep","image":"detective/payload:phase0","imagePullPolicy":"Never",
  "args":["sweep","-target","http://$ip:8080","-timeout","${TIMEOUT:-5s}","-only","${ONLY:-}"],
  "securityContext":{"allowPrivilegeEscalation":false,"readOnlyRootFilesystem":true,"capabilities":{"drop":["ALL"]}}}]}}
JSON
)
kubectl --context "$ctx" -n phase0 run "$name" --image=detective/payload:phase0 --restart=Never --overrides="$overrides" >/dev/null
for _ in $(seq 1 180); do
  case "$(kubectl --context "$ctx" -n phase0 get pod "$name" -o jsonpath='{.status.phase}')" in
    Succeeded|Failed) break ;;
  esac
  sleep 1
done
kubectl --context "$ctx" -n phase0 logs "$name"
phase=$(kubectl --context "$ctx" -n phase0 get pod "$name" -o jsonpath='{.status.phase}')
kubectl --context "$ctx" -n phase0 delete pod "$name" --wait=false >/dev/null
echo "RESULT green->$dst: $phase"
[ "$phase" = Succeeded ]
