#!/usr/bin/env bash
# Break/fix N times. Broken: healthz + GETs pass, POSTs >= 16K fail. Fixed: everything passes.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
runs="${1:-20}"; ok=0
for i in $(seq 1 "$runs"); do
  ./culprit.sh break >/dev/null
  out=$(./sweep.sh blue)
  broken_ok=no
  if echo "$out" | grep -q "^PASS GET         64" \
     && [ "$(echo "$out" | grep -c '^FAIL POST')" -eq 5 ] \
     && [ "$(echo "$out" | grep -c '^FAIL GET')" -eq 0 ]; then broken_ok=yes; fi
  ./culprit.sh fix >/dev/null
  fixed_ok=no; ./sweep.sh blue >/dev/null && fixed_ok=yes
  [ "$broken_ok" = yes ] && [ "$fixed_ok" = yes ] && ok=$((ok+1))
  echo "run $i: broken-as-expected=$broken_ok fixed=$fixed_ok"
done
echo "RESULT: $ok/$runs runs behaved as expected"
