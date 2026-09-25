# Scenes

One script per talk beat, in `scenes/`. Each is idempotent and prints what it
does. Run them in order; `make reset` goes back to the start from anywhere.

| Make target | Script | Chapter | What happens |
|---|---|---|---|
| `make reset` | `00-crime.sh` | before the talk | The "2am" state: every Argo CD app Synced/Healthy, prod's users failing |
| `make scene-2` | `02-cold-case.sh` | 2, warm-up | Hubble finds the policy drop in `cold-case` in seconds |
| `make scene-4` | `04-capture.sh` | 4, packets | Live tcpdump of frontdesk's uploads to the blue node: retransmissions, no ICMP. `--save` writes a pcap |
| `make scene-5` | `05-reveal.sh` | 5, reveal | `git log` / `git show` on `rendered/node-network/prod`: the MTU commit |
| `make scene-5-fix` | `05-reveal.sh --fix` | 5, fix | Revert the culprit; node-network auto-promotes the fix to staging and prod |
| `make scene-6` | `06-never-again.sh` | 6, never again | Merge the gate, re-push the culprit, watch staging's verification fail and prod refuse it |

## The `live` branch

Kargo watches `live`, not `main` (`bootstrap/kargo-apps.yaml` and both
Warehouses). The scenes commit to `live`: the culprit, the fix, the Chapter 6
merge. `make reset` rebuilds `live` from `main` every time, so:

- `main` stays clean for anyone reading or forking the repo;
- rehearsals are repeatable;
- a change to `apps/*` or `apps/*/kargo` on `main` reaches Kargo on the next
  `make reset`.

The scenes work in their own clone (`.cache/scene-repo`) and push with your
normal git credentials. They never touch your working tree.

## Why each reset makes a new platform commit

Kargo auto-promotes the **newest** Freight into a Stage with auto-promotion on
(both of node-network's Stages, and case-file's staging). After a run, the
newest node-network Freight is the culprit, so simply promoting an older
"good" Freight would be undone straight away. Instead, each reset adds a
baseline commit on `live` ("platform: pin node-tuner MTU to 1500 on both
pools"). That becomes the newest Freight, and the culprit, fix and re-push
that follow are each newer again. The commits only touch node-tuner and
`apps/node-network/CHANGELOG.md` (which isn't rendered).

## Timings (measured on OrbStack)

See the table at the end of Phase 5 in the build plan; `make reset` takes a
few minutes, most of it case-file's first verification after `main` changes.

## If something goes wrong on stage

- Anything odd: `make reset`, then carry on from the chapter you were in.
- `scene-4` hangs: it captures from the green node on purpose (the blue node's
  kubelet is unreachable while it's broken). Use the pre-captured pcaps in
  `evidence/`.
- `scene-6` needs `scene-5-fix` first (it re-pushes by reverting the fix).
