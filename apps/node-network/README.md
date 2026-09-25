# node-network

**The culprit's path.** Platform-owned node configuration, promoted by Kargo
from `staging` to `prod`, same rendered-manifests pattern as `case-file`.

It runs `node-tuner`: one DaemonSet per node pool, each declaring that pool's
underlay MTU (`--mtu=1500` for both, in the baseline). The tuner sets the
node's `eth0` MTU and keeps it there.

In the 2am state this pipeline has **no verification**: it's "just platform
config", so new Freight auto-promotes through `staging` and `prod` with nobody
looking. The culprit is one line in `base/node-tuner-blue.yaml`.

`node-tuner` is the one workload that isn't locked down: it runs as root with
`hostNetwork` and only the `NET_ADMIN` capability (not `privileged`), in its
own namespace with the `privileged` Pod Security level.

The Warehouse only watches git (`apps/node-network`), not the image: a
case-file release never creates node-network Freight.
