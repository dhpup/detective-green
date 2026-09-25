# cold-case

**The warm-up case (Plot B), solved in about 10 seconds.** Prod only, Argo CD
only, in its own namespace, not part of any pipeline.

v1.3 of a small client now calls the new `fingerprints` service on port 9090.
The namespace's default-deny CiliumNetworkPolicy only allows the old port,
8080, so every request is dropped. The client just retries and times out; no
probe fails, nothing turns red.

```bash
scenes/02-cold-case.sh    # hubble observe --verdict DROPPED -n cold-case
```

Hubble names it straight away: `Policy denied`. "Too easy. That's not our
culprit." The real case is the one Hubble reports as FORWARDED.

Not in staging on purpose: staging's gate fails on Hubble `POLICY_DENIED`
drops, so a permanent warm-up case there would block every promotion.
