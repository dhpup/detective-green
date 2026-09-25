# The gate

Chapter 6's payoff: Kargo verification on the `staging` Stage, so Freight only
becomes eligible for `prod` after the app demonstrably works. The checks live in
`kargo-shared/` as Argo Rollouts `ClusterAnalysisTemplate`s, so every Kargo
Project can use them, and the same files work for Argo Rollouts canary analysis.

## What it checks

| Check | How | Passes when |
|---|---|---|
| `payload-sweep` | Job in the Kargo cluster, `case-file sweep` against staging's frontdesk (NodePort 30080) | every size 1K..4M, download and upload, 4x each, succeeds |
| `interface-drops` | Prometheus (staging) | eth0 receive drops + errors, summed over all nodes, didn't increase in the last 3m |
| `large-payload-success` | Prometheus (staging) | informant's large requests >= 99% OK over 2m |
| `policy-drops` | Prometheus (staging) | no Hubble `POLICY_DENIED` drops over 2m (catches the warm-up case) |

The Prometheus checks wait 75 s (`initialDelay`) so their windows include the
sweep. When the sweep fails, Argo Rollouts ends the run straight away and the
remaining checks are skipped: one failure is enough.

A failed sweep leaves the evidence in its Job log, straight from frontdesk:

```
FAIL POST   16K  attempt 4/4    4006ms  504 upload handler timed out: evidence-locker 10.42.1.192
on node k3d-staging-agent-1 did not finish after 4.002s: Post "http://10.42.1.192:8080/api/evidence":
context deadline exceeded (5 TCP retransmits)
```

## Where it's used

- `case-file`'s staging Stage: from day one.
- `node-network`'s staging Stage: only on branch `scene-6/gate-the-platform`,
  merged live in Chapter 6 (the platform's pipeline had no gate at 2am).

## Run it by hand

```bash
hack/gate-check.sh    # builds the same AnalysisRun, prints each check, exits 1 on failure
```

## How reliable it is

Measured on the lab (Phase 4), with the culprit applied the real way (node-tuner
holding the blue node at MTU 1450):

| | Runs | Result |
|---|---|---|
| Broken (blue at 1450) | 10 | gate failed 10/10 |
| Healthy | 10 | gate passed 10/10 |

Leave about 3 minutes after a break is fixed before expecting a pass: the
Prometheus checks look back 2–3 minutes and would still see the drops.
