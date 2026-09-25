# informant

A continuous prober that plays the city's users (Argo CD only, no Kargo). It
sends a steady mix of small and large downloads and uploads through
`frontdesk` in each cluster, each on a fresh connection, and exports success
and latency by size bucket and destination node. In prod it's the users who
start timing out at 2am.

Pinned to `case-file` v1.2.0 by digest; it's not part of the case-file
pipeline, so a case-file release never changes it.
