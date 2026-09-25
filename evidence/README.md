# Evidence

Packet captures of the MTU black hole, and a Wireshark profile for walking
through them. The walkthrough in Chapter 4 uses these files, so it never
depends on live traffic.

| File | What it shows |
|---|---|
| `phase0-blackhole-green-eth0.pcap` | An upload from a green-node pod to a blue-node pod: handshake, full-size segments, 8 retransmissions with exponential backoff, no ICMP |
| `phase0-pair-sender-green-eth0.pcap` | The same failure, captured on the sender's node... |
| `phase0-pair-receiver-blue-eth0.pcap` | ...and at the same time on the receiver's node: 3,861 full-size frames sent, 0 received |

All were captured on each node's `eth0`, so the TCP traffic is inside VXLAN.
Wireshark decodes it automatically (UDP port 8472 is Cilium's VXLAN port; if
it doesn't, use *Decode As… → UDP port 8472 → VXLAN*).

## Wireshark profile

`wireshark-profile/` holds coloring rules and saved display filters. Copy the
folder into your Wireshark profiles directory as `detective-green`, or import
the files from *View → Coloring Rules* and the filter bookmarks.

| Filter | Why |
|---|---|
| `tcp.analysis.retransmission` | The same segment, sent again and again |
| `icmp.type == 3 && icmp.code == 4` | "Fragmentation needed": empty, and that's the point |
| `tcp.len >= 1300` | Full-size segments: these are the ones that vanish |

## Capture your own

```bash
scenes/04-capture.sh          # live tcpdump in frontdesk's network namespace (prod)
scenes/04-capture.sh --save   # write a pcap into evidence/
```
