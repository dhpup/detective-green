# Reproducing the MTU black hole

Phase 0 goal: on a laptop, small requests pass and large ones hang, every time. This is the write-up of how we got there and what we learned.

**Result:** reproduced on k3d + OrbStack with Cilium 1.20.2 in VXLAN mode, **20/20 break/fix cycles**. See [Reliability](#reliability).

## One-command repro

```bash
hack/phase0/up.sh           # cluster + Cilium + servers, then breaks blue and runs a sweep
hack/phase0/culprit.sh fix  # restore the blue node's MTU
hack/phase0/reliability.sh 20
hack/phase0/down.sh
```

| File | What it does |
|---|---|
| `k3d-phase0.yaml` | 1 server + 2 agents (`pool=green`, `pool=blue`), flannel/traefik/servicelb/network policy off |
| `mount-bpf.sh` | Mounts bpffs and a cgroup v2 path inside each k3d node, which Cilium needs |
| `offloads-off.sh` | Turns off segmentation offload on each node's `eth0`, and GRO/segmentation offload on the VM-side veths of this cluster's bridge (see finding 1) |
| `cilium-values.yaml` | Cilium in VXLAN mode, MTU pinned to 1500, TCP MTU probing off (see findings 2 and 3) |
| `cilium-values-native.yaml` | Overlay for the native routing test only (see finding 6). Not used by the demo |
| `payload/` | Tiny Go tool: `serve` returns/accepts N bytes, `sweep` tries 1K–4M GET and POST on fresh connections |
| `culprit.sh` | `break` sets the blue node's `eth0` MTU to 1450, `fix` sets it back to 1500 |
| `sweep.sh` | Runs one sweep from a client pod on green to the server on blue. `ONLY=post` or `ONLY=get` runs one direction |

## Environment

| | |
|---|---|
| Runtime | OrbStack 2.2.3, kernel `7.0.14-orbstack`, 8 CPU / 16 GB |
| k3d / k3s | v5.9.0 / `rancher/k3s:v1.35.5-k3s1` for Phase 0. The lab later moved to v1.36.4 (see `versions.env`), and the black hole re-verified 5/5 on the lab's staging cluster |
| Cilium | 1.20.2, `routingMode: tunnel`, `tunnelProtocol: vxlan`, kube-proxy kept |
| Docker network MTU | 1500 |
| `net.ipv4.tcp_mtu_probing` (node) | 0 |

## What it looks like

With the blue node's `eth0` at 1450 and everything else assuming 1500:

```
PASS GET         64 bytes      0ms      <- healthz-sized: fine
PASS GET      16384 bytes      0ms      <- downloads (blue -> green): fine
FAIL POST     16384 bytes   5004ms      <- uploads (green -> blue): hang until timeout
...
FAIL POST   4194304 bytes   5004ms
```

Uploads hang and downloads work. That matches the story's "file uploads hang" symptom. Downloads survive because the blue node's kernel fragments the outer VXLAN packet on the way out. Uploads die because green sends full 1500-byte frames, and the blue node's `eth0` (MTU 1450) drops them on arrival.

**The pcap** (`evidence/phase0-blackhole-green-eth0.pcap`, captured on green's `eth0`) shows the textbook signature:

1. The handshake completes, with MSS 1410 on both sides.
2. The client sends 1398-byte segments. A smaller 1300-byte segment gets through, but the server only sends duplicate `ack 1`.
3. `seq 1:1399` is retransmitted 8 times with exponential backoff (4 ms, 200 ms, 400 ms, 800 ms, 1.6 s, 3.2 s, 6.5 s, 13 s).
4. **No ICMP "fragmentation needed" anywhere in the VM.** The only ICMP seen is Cilium's health-check pings.

Wireshark filters: `tcp.analysis.retransmission`, `icmp.type==3 && icmp.code==4` (empty), `frame.len > 1400`.

**Hubble:** 64 flows to the blue server, all `FORWARDED`, 0 `DROPPED`. Red herring #2 holds: the packet dies at the receiving veth, outside Cilium's datapath.

**The fix:** setting the MTU back to 1500 heals new connections straight away, with no pod or Cilium restarts.

## Findings

### 1. veth offload hides the bug unless it's turned off
With segmentation offload on (the default), large "super-packets" (4–7 KB) cross the 1450-MTU interface untouched, because Linux skips the MTU check on the veth for offloaded packets. A real NIC splits packets into wire-sized frames, so a real wire doesn't behave this way. `offloads-off.sh` turns off `tso`, `gso` and UDP tunnel segmentation on each node's `eth0`.

The native routing test (finding 6) turned up a second place: **GRO on the VM-side veths** of the Docker bridge merged plain TCP segments back into 32 KB packets before they reached blue. VXLAN's UDP packets weren't merged, which is why VXLAN reproduced without this. `offloads-off.sh` now also turns off GRO/TSO/GSO on the VM-side veths, limited to the cluster's own bridge so other clusters aren't touched.

Both have to be part of cluster setup, and both reset if a node container restarts.

### 2. Cilium's MTU auto-detection heals a node-local change
With `MTU: 0` (the default), Cilium's MTU manager saw `eth0` drop to 1450 and updated every endpoint's route MTU within seconds (`job-mtu-updater: MTU updated (1450)`). The blue pods then advertised a smaller MSS and nothing broke. To reproduce the incident, the platform has to pin Cilium's MTU (`MTU: 1500`). Plenty of platforms do that, and it gives the story its real culprit: *two platform settings that disagree*.

### 3. Cilium's TCP MTU probing turns the hang into a 3-second stall
With `pmtuDiscovery.packetizationLayerPMTUDMode: blackhole` (the default), pods have TCP MTU probing on in black-hole mode. Uploads still hit the black hole, but recover after ~3.1 s once TCP shrinks its segments. To get a hard hang, we set it to `disabled`.

**Why findings 2 and 3 matter for the talk:** modern Cilium defaults defend against this failure. That's a good beat for Christian, and it's honest: in production the MTU drop is often somewhere in the fabric (a switch, a router, a cloud path) that the node can't see, and a 3-second stall still breaks clients with short timeouts. We should say on stage which defaults were changed and why.

### 4. Node-level TCP retransmit counters don't see pod traffic
During failing sweeps, the node's `Tcp: RetransSegs` (what node-exporter reports as `node_netstat_Tcp_RetransSegs`) barely moved (26 → 28). Pod TCP retransmits are counted inside each pod's network namespace, not the node's. So **node-exporter can't be the retransmit source for the gate**. D9 now reads retransmits from each connection's `TCP_INFO` in our own sweep and prober instead.

### 5. The drop counter on the blue node's `eth0` is clean
`/sys/class/net/eth0/statistics/rx_dropped` on the blue node went 160 → 239 during one failing sweep, and stayed flat otherwise. The matching VM-side veth showed the same number as `tx_dropped`. Green's counters stayed at 0. node-exporter exposes this as `node_network_receive_drop_total{device="eth0"}`, which makes it a precise, zero-baseline gate signal.

## Reliability

`reliability.sh 20`: each cycle breaks the blue node, runs a sweep, fixes it, and runs another sweep. A cycle passes only if, while broken, the healthz-sized request and all GETs pass and all 5 POSTs of 16K and up fail, **and** everything passes once fixed.

**Result: 20/20.** About 35 s per cycle, most of it the 5 s POST timeouts.

### 6. Native routing heals itself; VXLAN doesn't
With `routingMode: native` (`cilium-values-native.yaml`) and offload off everywhere:

| Sweep | Result |
|---|---|
| Uploads only (`ONLY=post`) | **Black hole:** every POST of 16K and up hangs |
| Default sweep (a large GET before each POST) | **Passes** |

Why: in native mode, blue's own kernel routes the pod's traffic out through the 1450-MTU `eth0`. The first large *download* (blue → green) is too big for it, so blue's kernel sends the blue pod a local ICMP "need to frag (mtu 1450)" (captured on the pod's `lxc` interface). The pod caches that path MTU for the client, and from then on advertises a smaller MSS to it, so uploads from that client work too. In VXLAN mode, the kernel fragments the *outer* tunnel packet instead, so no ICMP ever reaches the pod and nothing heals.

**Decision: the demo stays on VXLAN.** It gives a hard, repeatable black hole for uploads no matter what traffic came first. Native routing is still a good line for Christian: *"in native mode this particular break would half-heal itself; with a tunnel, nothing tells the pod."* After this test the cluster went back to VXLAN, and `reliability.sh 5` passed 5/5 with offload off everywhere.

### 7. Only a steady MTU gives a steady black hole
While testing the gate (Phase 4), forcing blue's MTU with a loop (`ip link set ... mtu 1450` every second) while node-tuner reset it to 1500 every 30 s made the black hole erratic: some sweeps lost 0 of 12 large uploads to blue, others 8. With node-tuner itself holding 1450 (what the culprit does), every upload to blue failed, 13 of 13 across three sweeps, and the gate failed 10/10. **Always break the node through node-tuner, never by racing it.**

## Still to test
- [x] Native routing mode (instead of VXLAN). See finding 6.
- [x] A capture on the blue node's `eth0` at the same time, to show the segment never arrives. During one failing sweep, green's `eth0` sent **3,861** full-size (≥1480-byte) VXLAN frames and blue's `eth0` received **0**. Files: `evidence/phase0-pair-sender-green-eth0.pcap` and `evidence/phase0-pair-receiver-blue-eth0.pcap`. This is the "it left the sender and never reached the receiver" beat for Chapter 4.
